// DO NOT EDIT.
//
// Generated by the Swift generator plugin for the protocol buffer compiler.
// Source: mlagents_envs/communicator_objects/brain_parameters.proto
//
// For information on using the generated types, please see the documentation:
//   https://github.com/apple/swift-protobuf/

import Foundation
import SwiftProtobuf

// If the compiler emits an error on this type, it is because this file
// was generated by a version of the `protoc` Swift plug-in that is
// incompatible with the version of SwiftProtobuf to which you are linking.
// Please ensure that you are building against the same version of the API
// that was used to generate this file.
fileprivate struct _GeneratedWithProtocGenSwiftVersion: SwiftProtobuf.ProtobufAPIVersionCheck {
  struct _2: SwiftProtobuf.ProtobufAPIVersion_2 {}
  typealias Version = _2
}

struct CommunicatorObjects_BrainParametersProto {
  // SwiftProtobuf.Message conformance is added in an extension below. See the
  // `Message` and `Message+*Additions` files in the SwiftProtobuf library for
  // methods supported on all messages.

  var vectorActionSize: [Int32] = []

  var vectorActionDescriptions: [String] = []

  var vectorActionSpaceType: CommunicatorObjects_SpaceTypeProto = .discrete

  var brainName: String = String()

  var isTraining: Bool = false

  var unknownFields = SwiftProtobuf.UnknownStorage()

  init() {}
}

// MARK: - Code below here is support for the SwiftProtobuf runtime.

fileprivate let _protobuf_package = "communicator_objects"

extension CommunicatorObjects_BrainParametersProto: SwiftProtobuf.Message, SwiftProtobuf._MessageImplementationBase, SwiftProtobuf._ProtoNameProviding {
  static let protoMessageName: String = _protobuf_package + ".BrainParametersProto"
  static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    3: .standard(proto: "vector_action_size"),
    5: .standard(proto: "vector_action_descriptions"),
    6: .standard(proto: "vector_action_space_type"),
    7: .standard(proto: "brain_name"),
    8: .standard(proto: "is_training"),
  ]

  mutating func decodeMessage<D: SwiftProtobuf.Decoder>(decoder: inout D) throws {
    while let fieldNumber = try decoder.nextFieldNumber() {
      switch fieldNumber {
      case 3: try decoder.decodeRepeatedInt32Field(value: &self.vectorActionSize)
      case 5: try decoder.decodeRepeatedStringField(value: &self.vectorActionDescriptions)
      case 6: try decoder.decodeSingularEnumField(value: &self.vectorActionSpaceType)
      case 7: try decoder.decodeSingularStringField(value: &self.brainName)
      case 8: try decoder.decodeSingularBoolField(value: &self.isTraining)
      default: break
      }
    }
  }

  func traverse<V: SwiftProtobuf.Visitor>(visitor: inout V) throws {
    if !self.vectorActionSize.isEmpty {
      try visitor.visitPackedInt32Field(value: self.vectorActionSize, fieldNumber: 3)
    }
    if !self.vectorActionDescriptions.isEmpty {
      try visitor.visitRepeatedStringField(value: self.vectorActionDescriptions, fieldNumber: 5)
    }
    if self.vectorActionSpaceType != .discrete {
      try visitor.visitSingularEnumField(value: self.vectorActionSpaceType, fieldNumber: 6)
    }
    if !self.brainName.isEmpty {
      try visitor.visitSingularStringField(value: self.brainName, fieldNumber: 7)
    }
    if self.isTraining != false {
      try visitor.visitSingularBoolField(value: self.isTraining, fieldNumber: 8)
    }
    try unknownFields.traverse(visitor: &visitor)
  }

  static func ==(lhs: CommunicatorObjects_BrainParametersProto, rhs: CommunicatorObjects_BrainParametersProto) -> Bool {
    if lhs.vectorActionSize != rhs.vectorActionSize {return false}
    if lhs.vectorActionDescriptions != rhs.vectorActionDescriptions {return false}
    if lhs.vectorActionSpaceType != rhs.vectorActionSpaceType {return false}
    if lhs.brainName != rhs.brainName {return false}
    if lhs.isTraining != rhs.isTraining {return false}
    if lhs.unknownFields != rhs.unknownFields {return false}
    return true
  }
}
