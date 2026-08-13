//--------------------------------------------------------------------------------------------------
//  Created by Pierre Molinaro on 13/08/2026.
//--------------------------------------------------------------------------------------------------

import SwiftUI
import Combine
import Synchronization

//--------------------------------------------------------------------------------------------------

@Observable @MainActor public final class AttributedStringBuffer {

  // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  /// Émet uniquement les *nouveaux* segments à ajouter (delta).
  /// La vue s'y abonne pour faire des appends incrémentaux dans le NSTextStorage.
  let appended = PassthroughSubject<String, Never>()
  /// Émis quand un clear() est demandé.
  let cleared = PassthroughSubject<Void, Never>()

  private let mPending = Mutex <[String]> ([])
  private var mTimer : Timer?

  // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  init (flushInterval inFlushInterval : TimeInterval) {
    self.mTimer = Timer.scheduledTimer(withTimeInterval: inFlushInterval, repeats: true) { _ in
      Task { @MainActor in self.flush() }
    }
  }

  // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

    /// Version String simple (convertie avec un style par défaut).
  nonisolated func append (line inLine: String, color: NSColor, bold: Bool) {
//    let font = NSFont.monospacedSystemFont (ofSize: 11, weight: bold ? .bold : .regular)
    self.mPending.withLock {
//      let at = NSAttributedString (
//        string: inLine + "\n",
//        attributes: [.foregroundColor: color, .font: font]
//      )
      $0.append (inLine)
    }
  }

  // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

    /// Version AttributedString (Swift, moderne).
//  nonisolated func append (attributedString line: AttributedString) {
//      var withNewline = line
//      withNewline.characters.append(contentsOf: "\n")
//      self.append(NSAttributedString(withNewline))
//  }

    /// Version NSAttributedString directe.
  nonisolated func append (_ inAT : String) {
    self.mPending.withLock { $0.append (inAT) }
  }

  // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  private nonisolated func flush() {
    let toAdd = self.mPending.withLock {
      let r = $0
      $0.removeAll()
      return r
    }

    var combined = String ()
    for piece in toAdd { combined.append(piece) }

    Task { @MainActor in
      self.appended.send (combined)
    }
  }

  // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  nonisolated func clear() {
    self.mPending.withLock { $0.removeAll () }
    Task { @MainActor in
      self.cleared.send ()
    }

//      lock.lock()
//      pending.removeAll()
//      lock.unlock()
//      DispatchQueue.main.async { [weak self] in
//          self?.cleared.send()
//      }
  }

  // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

}

//--------------------------------------------------------------------------------------------------

