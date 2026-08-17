//--------------------------------------------------------------------------------------------------
//  Created by Pierre Molinaro on 13/08/2026.
//--------------------------------------------------------------------------------------------------

import SwiftUI
import Combine
import Synchronization

//--------------------------------------------------------------------------------------------------

@Observable @MainActor public final class ConsoleTextBuffer {

  // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  nonisolated struct Element : Sendable {
    let string : String
    let foregroundColor : NSColor
    let backgroundColor : NSColor
  }

  // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  /// Émet uniquement les *nouveaux* segments à ajouter (delta).
  /// La vue s'y abonne pour faire des appends incrémentaux dans le NSTextStorage.
  let appended = PassthroughSubject<[Element], Never>()
  /// Émis quand un clear() est demandé.
  let cleared = PassthroughSubject<Void, Never>()

  private let mPending = Mutex <[Element]> ([])
  private var mTimer : Timer?

  // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  init (flushInterval inFlushInterval : TimeInterval) {
    self.mTimer = Timer.scheduledTimer(withTimeInterval: inFlushInterval, repeats: true) { _ in
      Task { @MainActor in self.flush () }
    }
  }

  // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  nonisolated func append (_ inElement : Element) {
    self.mPending.withLock { $0.append (inElement) }
  }

  // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  nonisolated func append (_ inElements : [Element]) {
    self.mPending.withLock { $0 += inElements }
  }

  // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  private nonisolated func flush() {
    let toAdd = self.mPending.withLock {
      let r = $0
      $0.removeAll()
      return r
    }
    Task { @MainActor in self.appended.send (toAdd) }
  }

  // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  nonisolated func clear () {
    self.mPending.withLock { $0.removeAll () }
    Task { @MainActor in self.cleared.send () }
  }

  // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

}

//--------------------------------------------------------------------------------------------------
