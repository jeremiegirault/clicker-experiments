//: Playground - noun: a place where people can play

import PlaygroundSupport
import UIKit
import Foundation

typealias Number = Double

extension Number {
    static let zero: Double = 0
}

//
// MARK: Number Textual Description
//

private extension Number {
    var frexp10: (Double, Int) {
        let exp = floor(log10(self))
        let mant = self / pow(10, exp)
        return (mant, Int(exp))
    }
}

private extension Int {
    static let alphabet = "abcdefghijklmnopqrstuvwxyz"
    static let suffixes: [String] = [ "K", "B", "M", "T", "Q" ]
    
    var gameSuffix: String {
        guard self >= 0 else { return "" }
        
        let third = self / 3
        if third < Int.suffixes.count {
            return Int.suffixes[third-1]
        } else {
            let initialDelta = self-3*Int.suffixes.count // start at aa after known suffixes
            let engineeringValue = initialDelta / 3
            let columnOffset = Int.alphabet.characters.count // start at aa by adding one alphabet
            return (engineeringValue+columnOffset).columnSuffix
        }
    }
    
    var columnSuffix: String { // not very nice recursive version but hey it seem to work
        guard self >= 0 else { return "" }
        // generate a, b, c... aa, bb, cc...
        let alphabetCount = Int.alphabet.characters.count
        let prefix = ((self / alphabetCount) - 1).columnSuffix
        let index = Int.alphabet.index(Int.alphabet.startIndex, offsetBy: (self % alphabetCount))
        let remainder = Int.alphabet[index]
        return prefix.appending(String(remainder)) // could be optimized
    }
}

extension Number {
    
    var gameDescription: String {
        if self.isNaN { return "NaN" }
        if self.isInfinite { return self > 0 ? "+∞" : "-∞" }
        
        if self >= 1e3 {
            let (mant, exp) = frexp10
            let remain = mant * pow(10.0, Double(exp % 3))
            return String(format: "%.2f%@", remain, exp.gameSuffix)
        } else {
            return String(format: "%.0f", self)
        }
        
    }
    
    var fullDescription: String {
        return "<Number value=\(self) gameDescription=\(gameDescription)>"
    }
}

//
// MARK: Resource
//

final class Resource {
    var value: Number = .zero
}

typealias Curve = (level: Int, value: Number) -> Number // describes a curve which depends on a level

enum Curves {
    static let linear: Curve = { level, value in return Double(level) * value }
    static let exponential: Curve = { level, value in return exp(Double(level)) * value }
}

class TickHandler {
    
    typealias OnTick = (delta: CFTimeInterval) -> Void
    
    let onTick: OnTick
    
    init(_ onTick: OnTick) {
        self.onTick = onTick
    }
}

extension TickHandler {
    
    static func resourceAutoIncrementer(resource: Resource, level: () -> Int, generationPerSecond: Number, curve: Curve) -> TickHandler {
        return TickHandler { delta in
            resource.value += delta * curve(level: level(), value: generationPerSecond)
        }
    }
    
    static func resourceIncrementer<T>(simulation: Simulation, increment: (T) -> Void) -> (T) -> Void {
        
        let incrementFunc: (T) -> Void = { argument in
            simulation.queue.async {
                if !simulation.paused {
                    increment(argument)
                }
            }
        }
        return incrementFunc
    }
}

final class Simulation {
    private let queue: DispatchQueue
    private let timer: DispatchSourceTimer
    private var lastTickTime: CFTimeInterval
    
    private(set) var totalDuration: CFTimeInterval
    let name: String
    
    var paused: Bool = true {
        didSet { if paused != oldValue { pausedDidChange() } }
    }
    
    var onTick: (() -> Void)? = nil
    
    init(name: String, interval: Double) {
        self.name = name
        queue = DispatchQueue(label: name)
        
        totalDuration = 0
        timer = DispatchSource.makeTimerSource(queue: queue)
        lastTickTime = CACurrentMediaTime()
        timer.scheduleRepeating(deadline: .now() + interval, interval: interval)
        timer.setEventHandler { [weak self] in self?.tick() }
    }
    
    private func tick() {
        let now = CACurrentMediaTime()
        let delta = now - lastTickTime
        
        update(delta: delta)
        
        self.lastTickTime = now
    }
    
    private func update(delta: CFTimeInterval) {
        guard delta > 0 else { return }
        
        tickHandlers.forEach { $0.onTick(delta: delta) }
        
        totalDuration += delta
    }
    
    private func pausedDidChange() {
        if paused {
            timer.suspend()
        } else {
            self.lastTickTime = CACurrentMediaTime()
            self.timer.resume()
        }
    }
    
    var tickHandlers = [TickHandler]()
    func addTickHandlers(handlers: [TickHandler]) {
        queue.async {
            handlers.forEach { self.tickHandlers.append($0) }
        }
    }
    
    func moveForward(interval: CFTimeInterval) {
        queue.async {
            self.update(delta: interval)
        }
    }
}

//
// MARK: Simulation Persistence
//

extension Simulation {
    var persistedData: Data {
        return Data()
    }
    
    convenience init?(persistedData: Data) {
        return nil
    }
}

let simulation = Simulation(name: "test", interval: 1)
let gold = Resource()

var gLevel = 1
let gGenerator = TickHandler.resourceAutoIncrementer(resource: gold, level: { gLevel }, generationPerSecond: 1, curve: Curves.exponential)

let ggClicker = TickHandler.resourceIncrementer(simulation: simulation) { () -> Void in
    gLevel += 100
}

//
// MARK: UI
//

class IncrementalViewController: UIViewController {
    
    lazy var stack = UIStackView()
    lazy var toggle = UISwitch()
    lazy var moveForward = UIButton(type: .system)
    lazy var goldLabel = UILabel()
    lazy var tapButton = UIButton(type: .system)
    lazy var updateButton = UIButton(type: .system)
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        view.backgroundColor = .white
        
        [ stack, toggle, moveForward, goldLabel, tapButton, updateButton ].forEach { $0.translatesAutoresizingMaskIntoConstraints = false }
        
        view.addSubview(stack)
        stack.addArrangedSubview(toggle)
        stack.addArrangedSubview(moveForward)
        stack.addArrangedSubview(goldLabel)
        stack.addArrangedSubview(tapButton)
        stack.addArrangedSubview(updateButton)
        
        updateButton.setTitle("Upgrade gold generation", for: .normal)
        updateButton.addTarget(self, action: #selector(updateGold), for: .touchUpInside)
        tapButton.setTitle("Tap for more gold !", for: .normal)
        tapButton.addTarget(self, action: #selector(tap), for: .touchDown)
        goldLabel.numberOfLines = 0
        toggle.addTarget(self, action: #selector(togglePaused), for: .valueChanged)
        moveForward.setTitle("Move Forward", for: .normal)
        moveForward.addTarget(self, action: #selector(moveForwardTouched), for: .touchUpInside)
        
        stack.axis = .vertical
        stack.alignment = .center
        
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            stack.topAnchor.constraint(equalTo: topLayoutGuide.bottomAnchor)
        ])
    }
    
    func updateGold() {
        ggClicker()
    }
    
    func tap() {
        gClicker()
    }
    
    func moveForwardTouched() {
        simulation.moveForward(interval: 120)
    }
    
    func togglePaused() {
        simulation.paused = !simulation.paused
    }
    
    func refresh() {
        let infos = [
            "gold: \(gold.value.gameDescription) (level: \(gLevel))",
            "duration: \(Int(simulation.totalDuration))s",
        ]
        self.goldLabel.text = infos.joined(separator: "\n")
    }
}

let viewController = IncrementalViewController()

let gClicker = TickHandler.resourceIncrementer(simulation: simulation) { () -> Void in
    gold.value += 10
    DispatchQueue.main.async { viewController.refresh() }
}

let UIUpdater = TickHandler { _ in DispatchQueue.main.async { viewController.refresh() } }

simulation.addTickHandlers(handlers: [
    gGenerator, UIUpdater
    ])

PlaygroundPage.current.liveView = viewController
