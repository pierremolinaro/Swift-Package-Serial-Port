//--------------------------------------------------------------------------------------------------

import Foundation

//--------------------------------------------------------------------------------------------------

public extension SerialPort {

  // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  enum BaudRate : Int, CaseIterable, RawRepresentable {

  //-  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -

  public typealias RawValue = Int // RawRepresentable

  //-  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -

    case baud50
    case baud75
    case baud110
    case baud134
    case baud150
    case baud200
    case baud300
    case baud600
    case baud1200
    case baud1800
    case baud2400
    case baud4800
    case baud9600
    case baud19200
    case baud38400
    case baud57600
    case baud115200
    case baud230400

    //-  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -

    public var speedValue : speed_t {
      switch self {
      case .baud50     : return speed_t(B50)
      case .baud75     : return speed_t(B75)
      case .baud110    : return speed_t(B110)
      case .baud134    : return speed_t(B134)
      case .baud150    : return speed_t(B150)
      case .baud200    : return speed_t(B200)
      case .baud300    : return speed_t(B300)
      case .baud600    : return speed_t(B600)
      case .baud1200   : return speed_t(B1200)
      case .baud1800   : return speed_t(B1800)
      case .baud2400   : return speed_t(B2400)
      case .baud4800   : return speed_t(B4800)
      case .baud9600   : return speed_t(B9600)
      case .baud19200  : return speed_t(B19200)
      case .baud38400  : return speed_t(B38400)
      case .baud57600  : return speed_t(B57600)
      case .baud115200 : return speed_t(B115200)
      case .baud230400 : return speed_t(B230400)
      }
    }

    //-  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -

    public var title : String {
      switch self {
      case .baud50     : return "50 bauds"
      case .baud75     : return "75 bauds"
      case .baud110    : return "110 bauds"
      case .baud134    : return "134 bauds"
      case .baud150    : return "150 bauds"
      case .baud200    : return "200 bauds"
      case .baud300    : return "300 bauds"
      case .baud600    : return "600 bauds"
      case .baud1200   : return "1 200 bauds"
      case .baud1800   : return "1 800 bauds"
      case .baud2400   : return "2 400 bauds"
      case .baud4800   : return "4 800 bauds"
      case .baud9600   : return "9 600 bauds"
      case .baud19200  : return "19 200 bauds"
      case .baud38400  : return "38 400 bauds"
      case .baud57600  : return "57 600 bauds"
      case .baud115200 : return "115 200 bauds"
      case .baud230400 : return "230 400 bauds"
      }
    }

    //-  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -

  }

  // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

}

//--------------------------------------------------------------------------------------------------
