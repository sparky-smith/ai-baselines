//
//  UnityEnv.swift
//  App
//
//  Created by Sercan Karaoglu on 19/04/2020.
//

import TensorFlow
import GRPC
import NIO
import Logging
import Version

struct Episode {
    struct Step {
        let observation: Tensor<Float>
        let action: Int32
    }

    let steps: [Step]
    let reward: Float
}

protocol Env {
    associatedtype BehaviorSpecImpl: BehaviorSpec
    typealias BehaviorMapping = [BehaviorName: BehaviorSpecImpl]
    
    var props: Props<BehaviorSpecImpl> { get set }
    var behaviorSpecs: BehaviorMapping { get }
    
    mutating func step() throws -> Void
    mutating func reset() throws-> Void
    mutating func close() throws -> Void
    mutating func setActions(behaviorName: BehaviorName, action: Tensor<BehaviorSpecImpl.Scalar>) throws -> Void
    mutating func setActionForAgent(behaviorName: String, agentId: AgentId, action: Tensor<BehaviorSpecImpl.Scalar>) throws -> Void
    func getSteps(behaviorName: BehaviorName) throws -> (DecisionSteps, TerminalSteps)?
}

struct Defaults {
    static let logger = Logger(label: "environments.UnityEnvironment")
    /**
    Communication protocol version.
    When connecting to C#, this must be compatible with Academy.k_ApiVersion.
    We follow semantic versioning on the communication version, so existing
    functionality will work as long the major versions match.
    This should be changed whenever a change is made to the communication protocol.
     */
    static let API_VERSION = "1.0.0"
    
    /**
     Default port that the editor listens on. If an environment executable
     isn't specified, this port will be used.
     */
    static let DEFAULT_EDITOR_PORT = 5004
    /* Default base port for environments. Each environment will be offset from this
     by it's worker_id.
     */
    static let BASE_ENVIRONMENT_PORT = 5005
    /// Command line argument used to pass the port to the executable environment.
    static let _PORT_COMMAND_LINE_ARG = "--mlagents-port"
}

struct Props<T: BehaviorSpec> {
    
    var isFirstMessage: Bool = true
    var communicator: RpcCommunicator
    var client: CommunicatorObjects_UnityToExternalProtoClient
    var sideChannelManager: SideChannelManager
    var loaded: Bool = false
    var envState: [String: (DecisionSteps, TerminalSteps)] = [:]
    var envSpecs: [String: T] = [:]
    var envActions: [String: Tensor<T.Scalar>] = [:]
}

extension Env {
    
    
    var client: CommunicatorObjects_UnityToExternalProtoClient {
        get { return props.client }
        set { props.client = newValue }
    }
    var isFirstMessage: Bool {
        get { return props.isFirstMessage }
        set { props.isFirstMessage = newValue }
    }
    var loaded: Bool {
        get { return props.loaded }
        set { props.loaded = newValue }
    }
    var envSpecs: [String: BehaviorSpecImpl] {
        get { return props.envSpecs }
        set { props.envSpecs = newValue }
    }
    var envState: [String: (DecisionSteps, TerminalSteps)] {
        get { return props.envState }
        set { props.envState = newValue }
    }
    var envActions: [String: Tensor<BehaviorSpecImpl.Scalar>] {
        get { return props.envActions }
        set { props.envActions = newValue }
    }
    var sideChannelManager: SideChannelManager {
        get { return props.sideChannelManager }
        set { props.sideChannelManager = newValue }
    }
    var communicator: RpcCommunicator {
        get { return props.communicator }
        set { props.communicator = newValue }
    }
    var behaviorSpecs: BehaviorMapping {
        get { return props.envSpecs }
    }
    
    static var logger: Logger {
        get { return Defaults.logger}
    }
    
    static func raiseVersionException(unityComVer: String) throws -> Void {
        throw UnityException.UnityEnvironmentException(reason: """
            The communication API version is not compatible between Unity and Swift.
            Swift API: \(Defaults.API_VERSION), Unity API: \(unityComVer).\n
        """)
    }
    
    static func checkCommunicationCompatibility(unityComVer: String, swiftApiVersion: String, unityPackageVersion: String) -> Bool {
        let unityCommunicatorVersion: Version = try! Version(unityComVer)
        let apiVersion: Version = try! Version(swiftApiVersion)
        if unityCommunicatorVersion.major != apiVersion.major{
            /// Major versions mismatch.
            return false
        } else if unityCommunicatorVersion.minor != apiVersion.minor {
            /// Non-beta minor versions mismatch.  Log a warning but allow execution to continue.
            logger.warning("""
                WARNING: The communication API versions between Unity and python differ at the minor version level.
                Swift API: \(swiftApiVersion), Unity API: \(unityCommunicatorVersion).\n
                This means that some features may not work unless you upgrade the package with the lower version.
                """)
        } else {
            logger.info("""
                Connected to Unity environment with package version \(unityPackageVersion)
                and communication version \(unityComVer)
            """)
        }
        return true
    }
    
    static func getCapabilitiesProto() -> CommunicatorObjects_UnityRLCapabilitiesProto{
        var capabilities = CommunicatorObjects_UnityRLCapabilitiesProto()
        capabilities.baseRlcapabilities = true
        return capabilities
    }
    
    static func warnCsharpBaseCapabilities(
        caps: CommunicatorObjects_UnityRLCapabilitiesProto, unityPackageVer: String, swiftPackageVer: String
    ) -> Void {
        if !caps.baseRlcapabilities {
            logger.warning("""
                WARNING: The Unity process is not running with the expected base Reinforcement Learning
                capabilities. Please be sure upgrade the Unity Package to a version that is compatible with this
                swift package.\n
                Python package version: \(swiftPackageVer), C# package version: \(unityPackageVer)
            """)
        }
    }
    
    init?(
        workerId: Int = 0,
        basePort: Int?,
        seed: Int = 0,
        noGraphics: Bool = false,
        timeoutWait: Int = 60,
        additionalArgs: [String]? = Optional.none,
        sideChannels: [SideChannel]? = Optional.none,
        logFolder: String? = Optional.none
        ) throws {
        try self.init(basePort: basePort)
        self.sideChannelManager = try SideChannelManager(sideChannels: sideChannels)
        let port: Int = Defaults.DEFAULT_EDITOR_PORT
        self.communicator = RpcCommunicator(workerId: workerId, port: port)
    }
    
    mutating func step() throws -> Void {
        if self.isFirstMessage {
            return try self.reset()
        }
        if !self.loaded {
            throw UnityException.UnityEnvironmentException(reason: "No Unity environment is loaded.")
        }
        for groupName in self.envSpecs.keys {
            if !(self.envActions.keys.contains(groupName)) {
                var nAgents = 0
                if self.envState.keys.contains(groupName){
                    nAgents = self.envState[groupName]?.0.len() ?? 0
                }
                self.envActions[groupName] = self.envSpecs[groupName]?.createEmptyAction(nAgents: nAgents)
            }
        }
        let stepInput = self.generateStepInput(vectorAction: self.envActions)
        // todo: measure time here
        if let outputs = self.communicator.exchange(inputs: stepInput) {
            self.updateBehaviorSpecs(output: outputs)
            let rlOutput = outputs.rlOutput
            try self.updateState(output: rlOutput)
            self.envActions.removeAll()
        } else {
            throw UnityException.UnityCommunicatorStoppedException(reason: "Communicator has exited.")
        }
    }
    
    mutating func reset() throws -> Void {
        if self.loaded {
            if let outputs = self.communicator.exchange(inputs: self.generateResetInput()){
                self.updateBehaviorSpecs(output: outputs)
                let rlOutput = outputs.rlOutput
                try self.updateState(output: rlOutput)
                self.isFirstMessage = false
                self.envActions.removeAll()
            } else {
                throw UnityException.UnityCommunicatorStoppedException(reason: "Communicator has exited.")
            }
        } else{
            throw UnityException.UnityEnvironmentException(reason: "No Unity environment is loaded.")
        }
    }
    
    /// Sends a shutdown signal to the unity environment, and closes the socket connection.
    mutating func close() throws -> Void {
        if self.loaded {
            self.loaded = false
            self.communicator.close()
        } else{
            throw UnityException.UnityEnvironmentException(reason: "No Unity environment is loaded.")
        }
    }
    
    mutating func setActions(behaviorName: BehaviorName, action: Tensor<BehaviorSpecImpl.Scalar>) throws -> Void {
        try self.assertBehaviorExists(behaviorName: behaviorName)
        if !self.envState.keys.contains(behaviorName) {
            return
        }
        if let actionSize = self.envSpecs[behaviorName]?.actionSize, let decisionStepLen = self.envState[behaviorName]?.0.len(){
            let expectedShape = TensorShape(decisionStepLen, actionSize)
            if action.shape != expectedShape{
                throw UnityException.UnityActionException(reason: """
                    The behavior \(behaviorName) needs an input of dimension \(expectedShape) for
                    (<number of agents>, <action size>) but received input of
                    dimension \(action.shape)
                    """)
            }
            self.envActions[behaviorName] = action
        }
    }
    
    func assertBehaviorExists(behaviorName: String) throws -> Void {
        if !self.envSpecs.keys.contains(behaviorName) {
            throw UnityException.UnityActionException(reason: """
                The group \(behaviorName) does not correspond to an existing agent group
                in the environment
            """)
        }
    }
    
    mutating func setActionForAgent(behaviorName: String, agentId: AgentId, action: Tensor<BehaviorSpecImpl.Scalar>) throws -> Void {
        try self.assertBehaviorExists(behaviorName: behaviorName)
        if !self.envState.keys.contains(behaviorName){
            return
        }
        if let spec = self.envSpecs[behaviorName]{
            let expectedShape = TensorShape([ spec.actionSize ])
            if action.shape != expectedShape {
                throw UnityException.UnityActionException(reason: """
                    The Agent \(agentId) with BehaviorName \(behaviorName) needs an input of dimension
                    \(expectedShape) but received input of dimension \(action.shape)
                    """
                )
            }

            if  !self.envActions.keys.contains(behaviorName), let nAgents = self.envState[behaviorName]?.0.len() {
                self.envActions[behaviorName] = spec.createEmptyAction(nAgents: nAgents)
            }
            
            guard let index = self.envState[behaviorName]?.0.agentId.firstIndex(where: {$0 == agentId}) else {
                throw UnityException.UnityEnvironmentException(reason: "agent_id \(agentId) is did not request a decision at the previous step")
            }
            self.envActions[behaviorName]?[index] = action
        }
    }
    
    func getSteps(behaviorName: BehaviorName) throws -> (DecisionSteps, TerminalSteps)? {
        try self.assertBehaviorExists(behaviorName: behaviorName)
        return self.envState[behaviorName]
    }
    
    func generateStepInput(vectorAction: [String: Tensor<BehaviorSpecImpl.Scalar>]) -> CommunicatorObjects_UnityInputProto {
        var rlIn = CommunicatorObjects_UnityRLInputProto()
        for b in vectorAction.keys {
            let nAgents = self.envState[b]?.0.len() ?? 0
            if nAgents == 0 {
                continue
            }
            for i in 0 ..< nAgents{
                var action = CommunicatorObjects_AgentActionProto()
                action.vectorActions = vectorAction[b]?[i].scalar as! [Float32]
                rlIn.agentActions[b]?.value += [action]
                rlIn.command = CommunicatorObjects_CommandProto.step
            }
        }
        rlIn.sideChannel = self.sideChannelManager.generateSideChannelMessages()
        
        return self.wrapUnityInput(rlInput: rlIn)
    }
    
    func generateResetInput() -> CommunicatorObjects_UnityInputProto {
        var rlIn = CommunicatorObjects_UnityRLInputProto()
        rlIn.command = CommunicatorObjects_CommandProto.reset
        rlIn.sideChannel = self.sideChannelManager.generateSideChannelMessages()
        return self.wrapUnityInput(rlInput: rlIn)
    }
    
    mutating func updateBehaviorSpecs(output: CommunicatorObjects_UnityOutputProto) -> Void {
        let initOutput = output.rlInitializationOutput
        for brainParam in initOutput.brainParameters {
            let agentInfos = output.rlOutput.agentInfos[brainParam.brainName]
            if let value = agentInfos?.value{
                let agent = value[0]
                let newSpec: BehaviorSpecImpl = behaviorSpecFromProto(brainParamProto: brainParam, agentInfo: agent)
                self.envSpecs[brainParam.brainName] = newSpec
                Self.logger.info("Connected new brain:\n \(brainParam.brainName)")
            }
        }
    }
    
    /// Collects experience information from all external brains in environment at current step.
    mutating func updateState(output: CommunicatorObjects_UnityRLOutputProto) throws -> Void {
        for brainName in self.envSpecs.keys {
            if output.agentInfos.keys.contains(brainName) {
                if let agentInfo = output.agentInfos[brainName], let envSpec = self.envSpecs[brainName] {
                    self.envState[brainName] = try stepsFromProto(agentInfoList: agentInfo.value, behaviorSpec: envSpec)
                }
            } else {
                if let envSpec =  self.envSpecs[brainName] {
                    self.envState[brainName] = (DecisionSteps.empty(spec: envSpec), TerminalSteps.empty(spec: envSpec))
                }
            }
        }
        try self.sideChannelManager.processSideChannelMessage(message: output.sideChannel)
    }
    func sendAcademyParameters(initParameters: CommunicatorObjects_UnityRLInitializationInputProto) -> CommunicatorObjects_UnityOutputProto? {
        var inputs = CommunicatorObjects_UnityInputProto()
        inputs.rlInitializationInput = initParameters
        return self.communicator.initialize(inputs: inputs)
    }
    func wrapUnityInput(rlInput: CommunicatorObjects_UnityRLInputProto) -> CommunicatorObjects_UnityInputProto {
        var result = CommunicatorObjects_UnityInputProto()
        result.rlInput = rlInput
        return result
    }

}

class UnityContinousEnvironment: Env {
    typealias BehaviorSpecImpl = BehaviorSpecContinousAction
    var props: Props<BehaviorSpecContinousAction>
    
    init(communicator co: RpcCommunicator, client cl: CommunicatorObjects_UnityToExternalProtoClient, sideChannelManager scm: SideChannelManager) {
        self.props = Props<BehaviorSpecContinousAction>(communicator: co, client: cl, sideChannelManager: scm)
    }
    
}

class UnityDiscreteEnvironment: Env {
    typealias BehaviorSpecImpl = BehaviorSpecDiscreteAction
    var props: Props<BehaviorSpecDiscreteAction>
    
    init(communicator co: RpcCommunicator, client cl: CommunicatorObjects_UnityToExternalProtoClient, sideChannelManager scm: SideChannelManager) {
        self.props = Props<BehaviorSpecDiscreteAction>(communicator: co, client: cl, sideChannelManager: scm)
    }
}
