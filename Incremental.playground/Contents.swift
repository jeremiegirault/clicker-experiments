//: Playground - noun: a place where people can play

import PlaygroundSupport
import UIKit
import Foundation

//
// MARK: Helpers
//

func log(_ message: @autoclosure () -> String, function: String = #function, file: String = #file, line: Int = #line) {
    print("[\(function)@\(line)] \(message())")
}

//
// MARK: Number
//

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

typealias Level = Int

struct Curve { // describes a curve which depends on a level
    typealias CurveFunction = (level: Level) -> Number
    
    let value: CurveFunction
    
    init(value: CurveFunction) {
        self.value = value
    }
    
    static func linear(initialValue: Double = 0, factor: Double = 1) -> Curve {
        return Curve { level in Double(level) * factor + initialValue }
    }
    
    static func exponential() -> Curve {
        return Curve { level in exp(Double(level)) }
    }
    
    static func flat(value: Double) -> Curve {
        return Curve { _ in value }
    }
}

//
// MARK: Domain Description
//

typealias Identifier = String

extension Identifier {
    static func newUniqueIdentifier() -> Identifier { return NSUUID().uuidString }
}

protocol Identifiable {
    var identifier: Identifier { get }
}

struct ResourceDescription: Identifiable {
    let identifier: Identifier
    let displayName: String
    
    init(identifier: Identifier = .newUniqueIdentifier(), displayName: String) {
        self.displayName = displayName
        self.identifier = identifier
    }
}


struct CostDescription {
    let resource: ResourceDescription
    let curve: Curve // in cost/level
}

protocol Upgradable: Identifiable {
    var curve: Curve { get }
}

struct UpgradeDescription<T: Upgradable>: Identifiable {
    let identifier: Identifier
    
    let target: T
    let costs: [CostDescription]
    
    init(identifier: Identifier = .newUniqueIdentifier(), target: T, costs: [CostDescription]) {
        self.identifier = identifier
        self.target = target
        self.costs = costs
    }
}

struct ResourceGeneratorFlags: OptionSet {
    typealias RawValue = Int
    let rawValue: Int
    
    init(rawValue: Int) { self.rawValue = rawValue }
    
    static let automatic = ResourceGeneratorFlags(rawValue: 1 << 0) // generates resource each tick
}

struct ResourceGeneratorDescription: Upgradable {
    let identifier: Identifier
    
    let resource: ResourceDescription
    let curve: Curve // in resource unit/s
    let flags: ResourceGeneratorFlags // maybe a set of enum would be better because associated types could help
    // for example cooldowns, conditions
    
    init(identifier: Identifier = .newUniqueIdentifier(), resource: ResourceDescription, curve: Curve, flags: ResourceGeneratorFlags = []) {
        self.identifier = identifier
        self.resource = resource
        self.curve = curve
        self.flags = flags
    }
}

//
// MARK: Resource
//

final class ResourceComponent {
    var value: Number = .zero
}

final class UpgradeComponent {
    var level: Level = 0
}

struct SimulationConfiguration {
    let timeMultiplier: Double
    
    static let defaultConfiguration = SimulationConfiguration(timeMultiplier: 1)
}

final class Simulation {
    private let queue: DispatchQueue
    private let timer: DispatchSourceTimer
    private var lastTickTime: CFTimeInterval
    private var configuration: SimulationConfiguration = .defaultConfiguration
    
    private var resources = [Identifier: ResourceComponent]()
    private var upgrades = [Identifier: UpgradeComponent]()
    private var generators = [ResourceGeneratorDescription]()
    
    private(set) var totalDuration: CFTimeInterval
    let name: String
    
    func update(configuration: SimulationConfiguration) {
        queue.async { self.configuration = configuration }
    }
    
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
        let delta = (now - lastTickTime) * configuration.timeMultiplier
        
        update(delta: delta)
        
        self.lastTickTime = now
    }
    
    private func update(delta: CFTimeInterval) {
        guard delta > 0 else { return }
        
        generators
            .filter { !$0.flags.isDisjoint(with: .automatic) }
            .forEach { generate(for: $0, multiplier: delta) }
        
        // call the ontick handler on main queue
        DispatchQueue.main.async { self.onTick?() }
        
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
    
    func fastForward(interval: CFTimeInterval) {
        queue.async {
            self.update(delta: interval)
        }
    }
    
    /// todo: make method below available from a transaction with locking with simulation update
    
    func register<T>(upgrade: UpgradeDescription<T>) {
        upgrades[upgrade.target.identifier] = UpgradeComponent()
    }
    
    func register(resource: ResourceDescription) {
        resources[resource.identifier] = ResourceComponent()
    }
    
    func register(automaticGenerator generator: ResourceGeneratorDescription) {
        generators.append(generator) // make it a set
    }
    
    func value(of resource: ResourceDescription) -> Number {
        guard let resourceComponent = resources[resource.identifier] else {
            log("ERROR> No Resource found for \(resource)")
            return 0
        }
        return resourceComponent.value
    }
    
    struct UpgradeInfo {
        let value: Number
        let level: Level
        let costs: [(String, Number)]
    }
    
    func info<T>(for upgradable: UpgradeDescription<T>) -> UpgradeInfo {
        guard let upgradeComponent = upgrades[upgradable.target.identifier] else {
            log("ERROR> No Upgrade found for \(upgradable)")
            return UpgradeInfo(value: 0, level: 0, costs: [])
        }
        
        let value = upgradable.target.curve.value(level: upgradeComponent.level)
        let costs = upgradable.costs.map { (costDescription: CostDescription) -> (String, Number) in
            let cost = costDescription.curve.value(level: upgradeComponent.level+1)
            return (costDescription.resource.displayName, cost)
        }
        return UpgradeInfo(value: value, level: upgradeComponent.level, costs: costs)
    }
    
    func upgrade<T>(_ upgradable: UpgradeDescription<T>) {
        guard let upgradeComponent = upgrades[upgradable.target.identifier] else {
            log("ERROR> No Upgrade found for \(upgradable)")
            return
        }
        
        var payments = [() -> Void]()
        for costDescription in upgradable.costs {
            guard let resource = resources[costDescription.resource.identifier] else {
                log("ERROR> No Resource found for \(costDescription)")
                return
            }
            
            let cost = costDescription.curve.value(level: upgradeComponent.level)
            if cost > resource.value {
                log("OOPS> Not Enough \(costDescription.resource) (\(resource.value)/\(cost))")
                return
            }
            
            payments.append { resource.value -= cost }
        }
        
        payments.forEach { $0() }
        upgradeComponent.level += 1
    }
    
    func generate(for resource: ResourceGeneratorDescription) {
        //guard resource.flags.isDisjoint(with: .automatic) else { return }
        generate(for: resource, multiplier: 1)
    }
    
    private func generate(for resource: ResourceGeneratorDescription, multiplier: Double) {
        guard let upgradeComponent = upgrades[resource.identifier] else {
            log("ERROR> No Upgrade found for \(resource)")
            return
        }
        guard let resourceComponent = resources[resource.resource.identifier] else {
            log("ERROR> No Resource found for \(resource)")
            return
        }
        
        resourceComponent.value += resource.curve.value(level: upgradeComponent.level)
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

//
// MARK: Game Instantiation
//

let gold = ResourceDescription(displayName: "👺")

let goldTapper = ResourceGeneratorDescription(resource: gold,
                                              curve: .linear(initialValue: 1, factor: 1))
let goldTapperUpgrade = UpgradeDescription(
    target: goldTapper,
    costs: [
        CostDescription(resource: gold,
                        curve: .linear(initialValue: 10, factor: 3))
    ])

let goldGenerator = ResourceGeneratorDescription(resource: gold,
                                                 curve: .linear(initialValue: 0, factor: 0.7),
                                                 flags: .automatic)
let goldGeneratorUpgrade = UpgradeDescription(
    target: goldGenerator,
    costs: [
        CostDescription(resource: gold,
                        curve: .exponential())
    ])

//
// MARK: UI
//

extension Simulation.UpgradeInfo {
    var userFacingCosts: String {
        return costs.map { name, price in "\(price.gameDescription) \(name)" }.joined(separator: ",")
    }
}

class IncrementalViewController: UIViewController {
    
    lazy var stack = UIStackView()
    lazy var toggle = UISwitch()
    lazy var moveForward = UIButton(type: .system)
    lazy var goldLabel = UILabel()
    lazy var tapButton = UIButton(type: .system)
    lazy var upgradeGoldGenButton = UIButton(type: .system)
    lazy var upgradeGoldTapButton = UIButton(type: .system)
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        view.backgroundColor = .white
        
        [ stack, toggle, moveForward, goldLabel, tapButton, upgradeGoldGenButton, upgradeGoldTapButton ].forEach { $0.translatesAutoresizingMaskIntoConstraints = false }
        
        view.addSubview(stack)
        stack.addArrangedSubview(toggle)
        stack.addArrangedSubview(moveForward)
        stack.addArrangedSubview(goldLabel)
        stack.addArrangedSubview(tapButton)
        stack.addArrangedSubview(upgradeGoldTapButton)
        stack.addArrangedSubview(upgradeGoldGenButton)
        
        
        upgradeGoldTapButton.setTitle("Upgrade gold Tap value", for: .normal)
        upgradeGoldTapButton.addTarget(self, action: #selector(upgradeGoldTap), for: .touchUpInside)
        upgradeGoldGenButton.setTitle("Upgrade gold generation", for: .normal)
        upgradeGoldGenButton.addTarget(self, action: #selector(upgradeGoldGeneration), for: .touchUpInside)
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
    
    func upgradeGoldTap() {
        simulation.upgrade(goldTapperUpgrade)
        refresh()
    }
    
    func upgradeGoldGeneration() {
        simulation.upgrade(goldGeneratorUpgrade)
        refresh()
    }
    
    func tap() {
        simulation.generate(for: goldTapper)
        refresh()
    }
    
    func moveForwardTouched() {
        simulation.fastForward(interval: 120)
    }
    
    func togglePaused() {
        simulation.paused = !simulation.paused
    }
    
    func refresh() {
        let goldTapInfo = simulation.info(for: goldTapperUpgrade)
        let goldGenInfo = simulation.info(for: goldGeneratorUpgrade)
        
        let infos = [
            "in my pocket: \(simulation.value(of: gold).gameDescription)\(gold.displayName)",
            "tap: level \(goldTapInfo.level) ~ \(goldTapInfo.value)/tap ~ upgrade for \(goldTapInfo.userFacingCosts)",
            "mine: level \(goldGenInfo.level) ~ \(goldGenInfo.value)/s ~ upgrade for \(goldGenInfo.userFacingCosts)",
            "duration: \(Int(simulation.totalDuration))s",
        ]
        self.goldLabel.text = infos.joined(separator: "\n")
    }
}

//
// MARK: UI Instantiation
//


let viewController = IncrementalViewController()
simulation.register(resource: gold)
simulation.register(automaticGenerator: goldGenerator)
simulation.register(upgrade: goldGeneratorUpgrade)
simulation.register(upgrade: goldTapperUpgrade)

log(">>>")
log("Upgrades   : \(simulation.upgrades)")
log("Resources  : \(simulation.resources)")
log("Generators : \(simulation.generators)")
log("<<<")


simulation.onTick = {
    viewController.refresh()
}

PlaygroundPage.current.liveView = viewController
