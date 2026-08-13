//--------------------------------------------------------------------------------------------------

import SwiftUI

//--------------------------------------------------------------------------------------------------

public struct SerialPortView : View {

  // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  @State private var mSerialPort : SerialPort

  // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  @State private var mSerialPortWatcher = SerialPortWatcher ()
  @State private var mSelectedSerialPortID : UUID? = nil

  // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  @AppStorage("show.only.usbserial.ports") private var mShowOnly_usbserial_Ports = true
  @State private var mPresentingPortSelectionDialog = false

  // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  @State private var mPresentingPortSettingDialog = false

  @AppStorage("port.baud.rate") private var mPortBaudRate = SerialPort.BaudRate.baud115200
  @State private var mTemporaryPortBaudRate = SerialPort.BaudRate.baud115200

  @AppStorage("port.parity") private var mPortParity = SerialPort.Parity.none
  @State private var mTemporaryPortParity = SerialPort.Parity.none

  @AppStorage("port.stop.bits") private var mPortStopBits = SerialPort.StopBits.one
  @State private var mTemporaryPortStopBits = SerialPort.StopBits.one

  // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  @State private var mPresentingPortConnectionProgress = false

  // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  public init (serialPort inSerialPort : SerialPort) {
    self.mSerialPort = inSerialPort
  }

  // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  public var body: some View {
    HStack {
      Button ("", systemImage: "gearshape.fill") { self.mPresentingPortSettingDialog = true }
      .labelStyle (.iconOnly)
      Button ("Connect…") { self.mPresentingPortSelectionDialog = true }
      .disabled (self.mSerialPort.isConnected)
      if !self.mSerialPort.isConnected, self.mSerialPortWatcher.mExposedSerialPorts.count == 1 {
        Button (self.mSerialPortWatcher.mExposedSerialPorts [0].title) {
          self.mSerialPort.openPort (
            withDescription: self.mSerialPortWatcher.mExposedSerialPorts [0],
            baudRate: self.mPortBaudRate,
            parity: self.mPortParity,
            stopBits: self.mPortStopBits
          )
          self.mPresentingPortConnectionProgress = true
        }.keyboardShortcut (.defaultAction)
      }
      if !self.mSerialPort.title.isEmpty {
        Text (self.mSerialPort.title).italic ()
      }
      if !self.mSerialPort.errorString.isEmpty {
        Text (self.mSerialPort.errorString).bold ().foregroundStyle (Color.red)
      }
      Text (self.mSerialPort.sendingStateString).foregroundStyle (Color (kSendColor))
      Text (self.mSerialPort.receivingStateString).foregroundStyle (Color (kReceiveColor))
//      .hiddenWhen (!self.mSerialPort.mReceivingStateReport)
      Spacer ()
      Button ("Disconnect") { self.mSerialPort.closePort (withMessage: nil) }
      .disabled (!self.mSerialPort.isConnected)
    }
    .padding (4)
    .sheet (isPresented: self.$mPresentingPortSelectionDialog) { self.portSelectionDialog () }
    .sheet (isPresented: self.$mPresentingPortSettingDialog) { self.portSettingDialog () }
    .sheet (isPresented: self.$mPresentingPortConnectionProgress) { self.portConnectionProgress () }
    .onAppear {
      self.mSerialPortWatcher.mShowOnly_usbserial_Ports = self.mShowOnly_usbserial_Ports
    }
    .onDisappear { self.mSerialPortWatcher.stopWatching () }
  }

  // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  private func portSelectionDialog () -> some View {
    VStack (spacing: 16) {
      AppIconView (title: "Select a serial port")
      Toggle ("Show only 'usbserial' ports", isOn: self.$mShowOnly_usbserial_Ports)
      if self.mSerialPortWatcher.mExposedSerialPorts.count == 0 {
        Text ("No serial port available").foregroundStyle (.secondary)
      }else if self.mSerialPortWatcher.mExposedSerialPorts.count == 1 {
        Button (self.mSerialPortWatcher.mExposedSerialPorts [0].title) {
          self.mSerialPort.openPort (
            withDescription: self.mSerialPortWatcher.mExposedSerialPorts [0],
            baudRate: self.mPortBaudRate,
            parity: self.mPortParity,
            stopBits: self.mPortStopBits
          )
          self.mPresentingPortSelectionDialog = false
          self.mPresentingPortConnectionProgress = true
        }
        .keyboardShortcut (.defaultAction)
      }else{
        ForEach (self.mSerialPortWatcher.mExposedSerialPorts, id: \.id) { port in
          Button (port.title) {
            self.mSerialPort.openPort (withDescription: port,
              baudRate: self.mPortBaudRate,
              parity: self.mPortParity,
              stopBits: self.mPortStopBits
            )
            self.mPresentingPortSelectionDialog = false
            self.mPresentingPortConnectionProgress = true
          }
        }
      }
      Button ("Cancel") { self.mPresentingPortSelectionDialog = false }
      .customCancelActionDecoration ()
    }
    .padding ()
    .onChange (of: self.mShowOnly_usbserial_Ports, initial: true) {
      self.mSerialPortWatcher.mShowOnly_usbserial_Ports = self.mShowOnly_usbserial_Ports
    }
  }

  // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  private func portSettingDialog () -> some View {
    VStack {
      AppIconView (title: "Port settings")
      Form {
        Picker ("Baud Rate", selection: self.$mTemporaryPortBaudRate) {
          ForEach (SerialPort.BaudRate.allCases, id:\.self) {
            Text ($0.title).tag ($0)
          }
        }.disabled (self.mSerialPort.isConnected)
        Picker ("Parity", selection: self.$mTemporaryPortParity) {
          ForEach (SerialPort.Parity.allCases, id:\.self) {
            Text ($0.title).tag ($0)
          }
        }.disabled (self.mSerialPort.isConnected)
        Picker ("Stop bits", selection: self.$mTemporaryPortStopBits) {
          ForEach (SerialPort.StopBits.allCases, id:\.self) {
            Text ($0.title).tag ($0)
          }
        }.disabled (self.mSerialPort.isConnected)
      }
      HStack {
        Button ("Cancel") { self.mPresentingPortSettingDialog = false }
        .customCancelActionDecoration (disabled: false)
        Spacer ()
        Button ("Save") {
          self.mPortBaudRate = self.mTemporaryPortBaudRate
          self.mPortParity = self.mTemporaryPortParity
          self.mPortStopBits = self.mTemporaryPortStopBits
          self.mPresentingPortSettingDialog = false
        }
        .keyboardShortcut (.defaultAction)
        .disabled (
          self.mSerialPort.isConnected
          ||
           ((self.mPortBaudRate == self.mTemporaryPortBaudRate)
            && (self.mPortParity == self.mTemporaryPortParity)
            && (self.mPortStopBits == self.mTemporaryPortStopBits)
          )
        )
      }
    }
    .padding ()
    .onAppear {
      self.mTemporaryPortBaudRate = self.mPortBaudRate
      self.mTemporaryPortParity = self.mPortParity
      self.mTemporaryPortStopBits = self.mPortStopBits
    }
  }

  // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  private func portConnectionProgress ()  -> some View {
    VStack (spacing: 16) {
      AppIconView (title: self.mSerialPort.isConnected ? "Connecting…" : "Disconnected")
      Button ("Cancel") {
        self.mPresentingPortConnectionProgress = false
        self.mSerialPort.closePort (withMessage: "User cancelled connection")
      }
      .customCancelActionDecoration ()
    }
    .padding ()
    .onChange (of: self.mSerialPort.isReady, initial: true) { (old, isReady) in
      if isReady {
        self.mPresentingPortConnectionProgress = false
      }
    }
  }

  // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

}

//--------------------------------------------------------------------------------------------------
