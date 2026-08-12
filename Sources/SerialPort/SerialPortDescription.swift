//--------------------------------------------------------------------------------------------------

import Foundation

//--------------------------------------------------------------------------------------------------

public struct SerialPortDescription : Identifiable {

  // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  public let id = UUID ()
  public let path : String
  public let productString : String?
  public let manufacturer : String?
  public let vendorID : UInt16?
  public let productID : UInt16?

  // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  public var vendorIDString : String {
    if let v = self.vendorID {
      return "0x" + String (v, radix: 16)
    }else{
      return "—"
    }
  }

  // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  public var productIDString : String {
    if let v = self.productID {
      return "0x" + String (v, radix: 16)
    }else{
      return "—"
    }
  }

  // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  public var title : String {
    if let p = self.productString, let m = self.manufacturer {
      return "\(p), \(m.trimmingCharacters(in: .whitespaces)) (\(self.path))"
    }else{
      return self.path
    }
  }

  // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

}

//--------------------------------------------------------------------------------------------------
