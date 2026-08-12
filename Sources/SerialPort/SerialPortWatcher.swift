//--------------------------------------------------------------------------------------------------

import Foundation
import Observation

//--------------------------------------------------------------------------------------------------

@Observable @safe final class SerialPortWatcher {

  // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  private var mAllSerialPorts : [SerialPortDescription] = [] {
    didSet { self.updateSerialPortList () }
  }

  private(set) var mExposedSerialPorts : [SerialPortDescription] = []

  // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  @ObservationIgnored private var mAddedIterator : io_iterator_t = 0
  @ObservationIgnored private var mRemovedIterator : io_iterator_t = 0
  @ObservationIgnored private var mNotificationPort : IONotificationPortRef? = nil
  @ObservationIgnored private var mIsStopping = false

  // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  var mShowOnly_usbserial_Ports : Bool = false {
    didSet { self.updateSerialPortList () }
  }

  // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  init () {
    self.startWatching ()
  }

  // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  func stopWatching () {
    // print ("stopWatching")
    self.mIsStopping = true
    if let notificationPort = unsafe self.mNotificationPort {
      let optRunLoopSource = unsafe IONotificationPortGetRunLoopSource(notificationPort)?.takeUnretainedValue ()
      if let runLoopSource = optRunLoopSource {
        CFRunLoopRemoveSource (CFRunLoopGetCurrent (), runLoopSource, .defaultMode)
      }
    }
    if self.mAddedIterator != 0 {
      IOObjectRelease (self.mAddedIterator)
      self.mAddedIterator = 0
    }
    if self.mRemovedIterator != 0 {
      IOObjectRelease (self.mRemovedIterator)
      self.mRemovedIterator = 0
    }
    if let notificationPort = unsafe self.mNotificationPort {
      unsafe IONotificationPortDestroy (notificationPort)
      unsafe self.mNotificationPort = nil
    }
  }

  // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  private func updateSerialPortList () {
    var exposedSerialPorts : [SerialPortDescription] = []
    for s in self.mAllSerialPorts {
      if !self.mShowOnly_usbserial_Ports || s.path.contains ("usbserial") {
        exposedSerialPorts.append (s)
      }
    }
    self.mExposedSerialPorts = exposedSerialPorts
  }

  // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  private func startWatching () {
    unsafe self.mNotificationPort = IONotificationPortCreate (kIOMainPortDefault)
    if let notificationPort = unsafe self.mNotificationPort {
      let optRunLoopSource = unsafe IONotificationPortGetRunLoopSource(notificationPort)?.takeUnretainedValue ()
      if let runLoopSource = optRunLoopSource {
        CFRunLoopAddSource (CFRunLoopGetCurrent (), runLoopSource, .defaultMode)
      }
    //--- Ajout
      unsafe IOServiceAddMatchingNotification (
        notificationPort,
        kIOMatchedNotification,
        unsafe IOServiceMatching (kIOSerialBSDServiceValue),
        { (optPtr, iterator) in
          if let ptr = unsafe optPtr {
            let obj = unsafe Unmanaged<SerialPortWatcher>.fromOpaque(ptr).takeRetainedValue()
            if !obj.mIsStopping {
              obj.handleAdded (iterator: iterator)
            }
          }
        },
        unsafe Unmanaged.passUnretained(self).toOpaque(),
        &self.mAddedIterator
      )
      self.handleAdded (iterator: self.mAddedIterator)
    //--- Retrait
      unsafe IOServiceAddMatchingNotification (
        notificationPort,
        kIOTerminatedNotification,
        unsafe IOServiceMatching (kIOSerialBSDServiceValue),
        { (optPtr, iterator) in
          if let ptr = unsafe optPtr {
            let obj = unsafe Unmanaged<SerialPortWatcher>.fromOpaque(ptr).takeRetainedValue()
            if !obj.mIsStopping {
              obj.handleRemoved (iterator: iterator)
            }
          }
        },
        Unmanaged.passUnretained (self).toOpaque(),
        &self.mRemovedIterator
      )
      self.handleRemoved (iterator: self.mRemovedIterator)
    }
  }

  // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  private func handleAdded (iterator inAddedIterator: io_iterator_t) {
    while case let service = IOIteratorNext (inAddedIterator), service != 0 {
      if let path = Self.stringProperty (service, key: kIOCalloutDeviceKey) {
        let productString = Self.stringProperty (service, key: kUSBProductString)
        let manufacturer = Self.stringProperty (service, key: kUSBVendorString)
        let vendorID = Self.uint16Property (service, key: kUSBVendorID)
        let productID = Self.uint16Property (service, key: kUSBProductID)
        let description = SerialPortDescription (
          path: path,
          productString: productString,
          manufacturer: manufacturer,
          vendorID: vendorID,
          productID: productID
        )
        self.mAllSerialPorts.append (description)
        // print ("Port ajouté : \(path)")
      }
      IOObjectRelease (service)
    }
  }

  // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  private func handleRemoved (iterator inRemovedIterator: io_iterator_t) {
    while case let service = IOIteratorNext (inRemovedIterator), service != 0 {
      if let path = Self.stringProperty (service, key: kIOCalloutDeviceKey) {
        // print("Port retiré : \(path)")
        self.mAllSerialPorts.removeAll { $0.path == path }
      }
      IOObjectRelease (service)
    }
  }

  // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  private static func stringProperty (_ inService : io_registry_entry_t,
                                      key inKey : String) -> String? {
    let cfProperty = unsafe IORegistryEntrySearchCFProperty (
      inService,
      kIOServicePlane,
      inKey as CFString,
      kCFAllocatorDefault,
      IOOptionBits (kIORegistryIterateParents | kIORegistryIterateRecursively)
    )
    return (cfProperty as? NSString) as? String
  }

  // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  private static func uint16Property (_ inService : io_registry_entry_t,
                                      key inKey : String) -> UInt16? {
    let cfProperty = unsafe IORegistryEntrySearchCFProperty (
      inService,
      kIOServicePlane,
      inKey as CFString,
      kCFAllocatorDefault,
      IOOptionBits (kIORegistryIterateParents | kIORegistryIterateRecursively)
    )
    return (cfProperty as? NSNumber)?.uint16Value
  }

  // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

}

//--------------------------------------------------------------------------------------------------
