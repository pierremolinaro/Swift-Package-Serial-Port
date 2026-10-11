//--------------------------------------------------------------------------------------------------
//  Created by Pierre Molinaro on 10/10/2026.
//--------------------------------------------------------------------------------------------------

import Foundation
import Observation
import Synchronization

//--------------------------------------------------------------------------------------------------

@MainActor @Observable open class BinaryCommandSerialPort <
             SEND_CODE : BinarySendCodeProtocol,
             RECEIVE_CODE : BinaryReceiveCodeProtocol> : SerialPort {

  // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  open nonisolated override func removeAllReceivedDatas () {
    self.mReceiverManager.withLock { $0 = ReceiverManager () }
  }

  // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
  //MARK: Send
  // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  public nonisolated func send (command inCommand : SEND_CODE) {
    var byte = inCommand.rawValue | 0xC0
    let data = unsafe Data (bytes: &byte, count: 1)
    self.sendData (data)
  }

  // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  public nonisolated func send (encodedU64 inValue : UInt64) {
    var data = Data ()
    data.append (UInt8 ((inValue & 0x0F) | 0x80))
    var v = inValue >> 4
    while v > 0 {
      data.append (UInt8 (v & 0x7F))
      v >>= 7
    }
    self.sendData (data)
  }

  // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  public nonisolated func send (encodedString inValue : String) {
    var data = Data ()
    data.append (0xA0)
    for utf32 in inValue.unicodeScalars {
      let pointCode : UInt32 = utf32.value
      if (pointCode >= 0x10) && (pointCode <= 0x1F) { // control 0001 xxxx
        data.append (UInt8 (pointCode))
        data.append (0x41) ;
      }else if pointCode <= 0x7F { // ASCII
        data.append (UInt8 (pointCode))
      }else if pointCode <= 0x3FF {
        data.append (UInt8 (pointCode & 0x0F) | 0x10)
        data.append (UInt8 (pointCode >> 4) | 0x40)
      }else if pointCode <= 0xFFFF {
        data.append (UInt8 (pointCode & 0x0F) | 0x10)
        data.append (UInt8 (pointCode >> 4) & 0x3F)
        data.append (UInt8 (pointCode >> 10) | 0x40)
      }else{
        data.append (UInt8 (pointCode & 0x0F) | 0x10)
        data.append (UInt8 (pointCode >> 4) & 0x3F)
        data.append (UInt8 (pointCode >> 10) & 0x3F)
        data.append (UInt8 (pointCode >> 16) | 0x40)
      }
    }
    self.sendData (data)
  }

  // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
  //MARK: Receive
  // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  private let mReceiverManager = Mutex <ReceiverManager <RECEIVE_CODE>> (ReceiverManager ())

  @ObservationIgnored private var mCompletionCallBack : Optional < @MainActor (_ inCommand : Command <RECEIVE_CODE>) -> Void > = nil

  // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  public func setCompletionCallBack (_ inCompletionCallBack : Optional < @MainActor  (_ inCommand : Command <RECEIVE_CODE>) -> Void >) {
    self.mCompletionCallBack = inCompletionCallBack
  }

  // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  nonisolated public override func handleReceivedData (_ inData : Data) {
//    var s = ""
//    for byte in inData {
//      s += " \(String (byte, radix: 16, uppercase: true))"
//    }
//    Swift.print ("Received[\(inData.count)]:\(s)")
    self.reportReceivingState (inData.count)
    for byte in inData {
      self.mReceiverManager.withLock { $0.handleReceivedByte (byte) }
    }
    self.mReceiverManager.withLock {
      while !$0.mCommands.isEmpty {
        let command = $0.mCommands.removeFirst ()
        Task { @MainActor in self.mCompletionCallBack? (command) }
      }
    }
  }

  // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

}

//--------------------------------------------------------------------------------------------------

nonisolated public enum Parameter : Sendable {
  case u64 (UInt64)
  case s64 (Int64)
  case str (String)

  public var u64 : UInt64? {
    switch self {
    case .u64 (let v): return v
    case .s64, .str: return nil
    }
  }

  public var s64 : Int64? {
    switch self {
    case .s64 (let v): return v
    case .u64, .str: return nil
    }
  }

  public var str : String? {
    switch self {
    case .str (let v): return v
    case .u64, .s64: return nil
    }
  }
}

//--------------------------------------------------------------------------------------------------

nonisolated public struct Command <RECEIVE_CODE : BinaryReceiveCodeProtocol> : Sendable {
  public let code : RECEIVE_CODE
  public let parameters : [Parameter]
}

//--------------------------------------------------------------------------------------------------

nonisolated struct ReceiverManager <RECEIVE_CODE : BinaryReceiveCodeProtocol> {

  // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  var mDecoderState = DecoderState.idle
  var mDecodingU64Value : UInt64 = 0
  var mDecodingU64Shift : UInt64 = 0
  var mDecodingString = Data ()
  var mParameterStack = [Parameter] ()
  var mCommands = [Command <RECEIVE_CODE>] ()

  // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  private enum ByteFormat {
    case parameterExtension
    case beginUnsigned
    case beginSigned
    case beginString
    case command
    case undefined
  } ;

  // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  private nonisolated static func formatForByte (_ inByte : UInt8) -> ByteFormat {
    var result = ByteFormat.undefined
    if (inByte & 0x80) == 0 {
      result = .parameterExtension
    }else if (inByte & 0xF0) == 0x80 {
      result = .beginUnsigned
    }else if (inByte & 0xF0) == 0x90 {
      result = .beginSigned
    }else if inByte == 0xA0 {
      result = .beginString
    }else if (inByte & 0xC0) == 0xC0 {
      result = .command
    }
    return result
  }

  // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  enum DecoderState {
    case idle
    case decodingUnsigned
    case decodingSigned
    case decodingString
    case error
  }

  // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

//  public enum Parameter {
//    case u64 (UInt64)
//    case s64 (Int64)
//    case str (String)
//
//    public var u64 : UInt64? {
//      switch self {
//      case .u64 (let v): return v
//      case .s64, .str: return nil
//      }
//    }
//
//    public var s64 : Int64? {
//      switch self {
//      case .s64 (let v): return v
//      case .u64, .str: return nil
//      }
//    }
//
//    public var str : String? {
//      switch self {
//      case .str (let v): return v
//      case .u64, .s64: return nil
//      }
//    }
//  }

  // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

//  @MainActor public struct Command {
//    public let code : RECEIVE_CODE
//    public let parameters : [Parameter]
//  }

  // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  private func decodeStringFromByteArray () -> String {
    var utf32Array = [UnicodeScalar] ()
    var multiByteShift : UInt32 = 0
    var utf32Value : UInt32 = 0
    for byte in self.mDecodingString {
      if multiByteShift > 0 {
        if (byte & 0x40) == 0 {
          utf32Value |= UInt32 (byte & 0x3F) << multiByteShift
          multiByteShift += 6
        }else{ // End of multi byte
          utf32Value |= UInt32 (byte & 0x3F) << multiByteShift
          utf32Array.append (UnicodeScalar (utf32Value)!)
          utf32Value = 0 ;
          multiByteShift = 0 ;
        }
      }else if byte >= 0x10, byte <= 0x1F { // Start multibyte
        utf32Value = UInt32 (byte & 0x0F)
        multiByteShift = 4
      }else{
        utf32Array.append (UnicodeScalar (byte))
      }
    }
    return String (String.UnicodeScalarView (utf32Array))
  }

  // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  private mutating func closeCurrentValueDecoding () {
    switch self.mDecoderState {
    case .decodingUnsigned :
      self.mParameterStack.append (.u64 (self.mDecodingU64Value))
      self.mDecoderState = .idle
    case .decodingSigned :
      let v = Int64 (bitPattern: ~self.mDecodingU64Value) ;
      self.mParameterStack.append (.s64 (v))
      self.mDecoderState = .idle
    case .decodingString :
      let s = self.decodeStringFromByteArray () ;
      self.mParameterStack.append (.str (s))
      self.mDecoderState = .idle
    case .idle :
      ()
    case .error :
      ()
    }
  }

  // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  mutating func handleReceivedByte (_ inByte : UInt8) {
    let f : ByteFormat = Self.formatForByte (inByte)
    switch f {
    case .parameterExtension :
      switch self.mDecoderState {
      case .decodingUnsigned :
        self.mDecodingU64Value |= UInt64 (inByte & 0x7F) << self.mDecodingU64Shift
        self.mDecodingU64Shift += 7
      case .decodingSigned :
        self.mDecodingU64Value |= UInt64 (inByte & 0x7F) << self.mDecodingU64Shift
        self.mDecodingU64Shift += 7
      case .decodingString :
        self.mDecodingString.append (inByte)
      case .idle :
        ()
      case .error :
        ()
      }
    case .beginUnsigned :
      self.closeCurrentValueDecoding ()
      self.mDecodingU64Value = UInt64 (inByte & 0x0F)
      self.mDecodingU64Shift = 4
      self.mDecoderState = .decodingUnsigned
    case .beginSigned :
      self.closeCurrentValueDecoding () ;
      self.mDecodingU64Value = UInt64 (inByte & 0x0F)
      self.mDecodingU64Shift = 4
      self.mDecoderState = .decodingSigned
    case .beginString :
      self.closeCurrentValueDecoding ()
      self.mDecodingString.removeAll ()
      self.mDecoderState = .decodingString
    case .command :
      self.closeCurrentValueDecoding ()
      if let receiveCode = RECEIVE_CODE (rawValue: inByte & 0x3F) {
        let command = Command (code: receiveCode, parameters: self.mParameterStack)
        self.mCommands.append (command)
      }
      self.mParameterStack.removeAll ()
    case .undefined :
      ()
    }
  }

 // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

}

//--------------------------------------------------------------------------------------------------

