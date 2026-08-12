//--------------------------------------------------------------------------------------------------

import SwiftUI
import Observation
import IOKit.serial
import IOKit.usb
import Synchronization

//--------------------------------------------------------------------------------------------------

let kReceiveColor = Color.green.mix (with: .black, by: 0.25)
let kSendColor = Color.red
let kCtrlCharacterBackColor = Color.gray.mix (with: .white, by: 0.85)

//--------------------------------------------------------------------------------------------------

@MainActor @Observable public class SerialPort {

  // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  public init () {
  }

  // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  private var mPath : String = ""
  let mFileDescriptor = Mutex <Int32?> (nil)

  // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  public var isConnected : Bool = false
  var isReady : Bool { self.isConnected }

  // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  private(set) var title = ""
  private(set) var errorString = ""

  // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
  //MARK: Properties for receiving data
  // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  var mReadSource : DispatchSourceRead? = nil
  let mReceiveQueue = DispatchQueue (label: "name.pcmolinaro.receive.queue", qos: .userInteractive)
  let mReceivedDataHandler = Mutex <ReceivedDataHandler> (ReceivedDataHandler ())

  // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
  //MARK: Sending State Report
  // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  private enum ReportPhase { case off, signaling, continueSignaling }

  // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  private var mSendingReportTimer : Timer? = nil
  private var mSendingStateReportPhase = ReportPhase.off
  private(set) var mSendingStateReport = false

  // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  @MainActor func reportSendingState () {
    switch self.mSendingStateReportPhase {
    case .signaling :
      self.mSendingStateReportPhase = .continueSignaling
    case .continueSignaling :
      ()
    case .off :
      self.mSendingStateReport = true
      self.mSendingStateReportPhase = .signaling
      self.mSendingReportTimer = Timer.scheduledTimer (withTimeInterval: 0.125,
                                                       repeats: false) { [weak self] _ in
        Task { @MainActor in
          self?.mSendingStateReport = false
          self?.mSendingReportTimer = Timer.scheduledTimer (withTimeInterval: 0.125,
                                                            repeats: false) { [weak self] _ in
            Task { @MainActor in
              self?.mSendingReportTimer = nil
              if let state = self?.mSendingStateReportPhase, state == .continueSignaling {
                self?.mSendingStateReportPhase = .off
                self?.reportSendingState ()
              }else{
                self?.mSendingStateReportPhase = .off
              }
            }
          }
        }
      }
    }
  }

  // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
  //MARK: Receiving State Report
  // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  private(set) var mReceivingStateReport = false
  private var mReceivingStateReportPhase = ReportPhase.off
  private var mReceivingReportTimer : Timer? = nil

  // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  @MainActor func reportReceivingState () {
    switch self.mReceivingStateReportPhase {
    case .signaling :
      self.mReceivingStateReportPhase = .continueSignaling
    case .continueSignaling :
      ()
    case .off :
      self.mReceivingStateReport = true
      self.mReceivingStateReportPhase = .signaling
      self.mReceivingReportTimer = Timer.scheduledTimer (withTimeInterval: 0.125,
                                                         repeats: false) { [weak self] _ in
        Task { @MainActor in
          self?.mReceivingStateReport = false
          self?.mReceivingReportTimer = Timer.scheduledTimer (withTimeInterval: 0.125,
                                                              repeats: false) { [weak self] _ in
            Task { @MainActor in
              self?.mReceivingReportTimer = nil
              if let state = self?.mReceivingStateReportPhase, state == .continueSignaling {
                self?.mReceivingStateReportPhase = .off
                self?.reportReceivingState ()
              }else{
                self?.mReceivingStateReportPhase = .off
              }
            }
          }
        }
      }
    }
  }

  // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
  //MARK: Console
  // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  public var mConsoleLogIsEnabled = false
  public var mConsoleAttributedString = AttributedString ()

  // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
  //MARK: Open port
  // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  @MainActor func openPort (withDescription inDescription : SerialPortDescription,
                            baudRate inBaudRate : BaudRate,
                            parity inParity : Parity,
                            stopBits inStopBits : StopBits) {
    self.mPath = inDescription.path
    self.title = inDescription.title
    self.errorString = ""
    if self.mPath.isEmpty {
      self.title = ""
      self.errorString = "Empty file path"
    }else{
      let flags : Int32 = O_RDWR | O_NOCTTY
      // O_RDWR: Read / write access
      // O_NOCTTY: If path refers to a terminal device—see tty(4)—it will not
      //     become the process's controlling terminal even if the
      //     process does not have one.
      let fileDescriptor = unsafe open (self.mPath, flags)
      if fileDescriptor > 0 {
        self.mFileDescriptor.withLock { $0 = fileDescriptor }
        Self.setSettings (
          baudRate: inBaudRate,
          parity: inParity,
          stopBits: inStopBits,
          fileDescriptor: fileDescriptor
        )
        self.isConnected = true
        self.setupReceive (fileDescriptor)
      }else{
        self.mFileDescriptor.withLock { $0 = nil }
        self.title = ""
        self.errorString = "Failed to open port"
      }
    }
  }

  // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  @MainActor private static func setSettings (baudRate inBaudRate : BaudRate,
                                              parity inParity : Parity = .none,
                                              stopBits inStopBits : StopBits = .one,
                                              dataBitsSize: DataBitsSize = .bits8,
                                              fileDescriptor inFileDescriptor : Int32,
                                              useHardwareFlowControl: Bool = false,
                                              useSoftwareFlowControl: Bool = false,
                                              processOutput: Bool = false) {
  //--- Set up the control structure
    var settings = termios ()
  //--- Get options structure for the port
    unsafe tcgetattr (inFileDescriptor, &settings)
  //--- Set baud rates
    unsafe cfsetispeed (&settings, inBaudRate.speedValue)
    unsafe cfsetospeed (&settings, inBaudRate.speedValue)
  //--- Enable parity (even/odd) if needed
    settings.c_cflag &= ~Parity.odd.parityValue
    settings.c_cflag |= inParity.parityValue
  //--- Set stop bit flag
    inStopBits.enterSetting (&settings)
  //--- Set data bits size flag
    settings.c_cflag &= ~tcflag_t(CSIZE)
    settings.c_cflag |= dataBitsSize.flagValue
  //--- Disable input mapping of CR to NL, mapping of NL into CR, and ignoring CR
    settings.c_iflag &= ~tcflag_t (ICRNL | INLCR | IGNCR)
  //-- Set hardware flow control flag
    if useHardwareFlowControl {
      settings.c_cflag |= tcflag_t (CRTS_IFLOW)
      settings.c_cflag |= tcflag_t (CCTS_OFLOW)
    }else{
      settings.c_cflag &= ~tcflag_t (CRTS_IFLOW)
      settings.c_cflag &= ~tcflag_t (CCTS_OFLOW)
    }
  //-- Set software flow control flags
    let softwareFlowControlFlags = tcflag_t (IXON | IXOFF | IXANY)
    if useSoftwareFlowControl {
      settings.c_iflag |= softwareFlowControlFlags
    }else{
      settings.c_iflag &= ~softwareFlowControlFlags
    }
  //--- Turn on the receiver of the serial port, and ignore modem control lines
    settings.c_cflag |= tcflag_t (CREAD | CLOCAL)
  //--- Turn off canonical mode
    settings.c_lflag &= ~tcflag_t (ICANON | ECHO | ECHOE | ISIG)
  //--- Set output processing flag
    if processOutput {
      settings.c_oflag |= tcflag_t (OPOST)
    }else{
      settings.c_oflag &= ~tcflag_t (OPOST)
    }
  //--- Special characters
  // We do this as c_cc is a C-fixed array which is imported as a tuple in Swift.
  // To avoid hardcoding the VMIN or VTIME value to access the tuple value, we use the typealias instead
    typealias specialCharactersTuple = (VEOF: cc_t, VEOL: cc_t, VEOL2: cc_t, VERASE: cc_t, VWERASE: cc_t, VKILL: cc_t, VREPRINT: cc_t, spare1: cc_t, VINTR: cc_t, VQUIT: cc_t, VSUSP: cc_t, VDSUSP: cc_t, VSTART: cc_t, VSTOP: cc_t, VLNEXT: cc_t, VDISCARD: cc_t, VMIN: cc_t, VTIME: cc_t, VSTATUS: cc_t, spare: cc_t)
    var specialCharacters : specialCharactersTuple = (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0) // NCCS = 20
    specialCharacters.VMIN = 0 // minimumBytesToRead == 0
    specialCharacters.VTIME = cc_t (20) // Unit: 0,1s
    settings.c_cc = specialCharacters
  //--- Commit settings
    unsafe tcsetattr (inFileDescriptor, TCSANOW, &settings)
  }

  // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
  //MARK: Close port
  // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  @MainActor func closePort (withMessage inMessage : String?) {
    self.title = ""
    self.isConnected = false
    if self.mFileDescriptor.withLock ({ $0 }) != nil {
      self.mFileDescriptor.withLock { $0 = nil }
      if let s = inMessage {
        self.errorString = s
      }
    }
  }

  // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
  //MARK: Console
  // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  public func clearConsole () {
    self.mConsoleAttributedString = AttributedString ()
  }

  // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

}

//--------------------------------------------------------------------------------------------------
