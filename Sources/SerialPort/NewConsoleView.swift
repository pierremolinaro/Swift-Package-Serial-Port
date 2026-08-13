//--------------------------------------------------------------------------------------------------
//  Created by Pierre Molinaro on 13/08/2026.
//--------------------------------------------------------------------------------------------------

import SwiftUI
import AppKit
import Synchronization

//--------------------------------------------------------------------------------------------------

/// Buffer thread-safe qui accumule les lignes entrantes et ne notifie
/// la vue qu'à intervalle régulier (batching), pour éviter un
/// re-render à chaque ligne reçue.
@Observable @MainActor public final class ConsoleBuffer {

  // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  private(set) var text: String = ""

  private let pending = Mutex<[String]> ([])
  private let maxLines: Int
  private var mTimer : Timer?
  private var lineCount = 0

  // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

    /// - Parameters:
    ///   - maxLines: nombre max de lignes conservées (ring buffer)
    ///   - flushInterval: fréquence de mise à jour de l'UI
  @MainActor public init (maxLines: Int = 5000, flushInterval: TimeInterval = 0.1) {
      self.maxLines = maxLines
      let timer = Timer.scheduledTimer(withTimeInterval: flushInterval, repeats: true) { [weak self] _ in
          self?.flush()
      }
      self.mTimer = timer
  }

  // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  /// Appelable depuis n'importe quel thread.
  nonisolated public func append (_ line: String) {
    self.pending.withLock { $0.append (line) }
  }

  // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  nonisolated private func flush () {
    let toAdd = self.pending.withLock {
      let r = $0
      $0.removeAll()
      return r
    }
    Task { @MainActor in
      self.text += toAdd.joined(separator: "\n") + "\n"
      self.lineCount += toAdd.count
      if self.lineCount > self.maxLines {
        let lines = self.text.split(separator: "\n", omittingEmptySubsequences: false)
        let trimmed = lines.suffix(self.maxLines)
        self.text = trimmed.joined(separator: "\n") + "\n"
        self.lineCount = trimmed.count
      }
    }
  }

  // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  nonisolated func clear () {
    self.pending.withLock { $0.removeAll () }
    Task { @MainActor in
      self.text = ""
      self.lineCount = 0
    }
  }

  // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

}

//--------------------------------------------------------------------------------------------------

/// Vue console basée sur NSTextView, bien plus performante que Text/List
/// pour de gros volumes de texte qui grossissent en continu.
public struct ConsoleTextView : NSViewRepresentable {

  // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  @State private var mBuffer : ConsoleBuffer
  private var mAutoScroll : Bool

  // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  public init (buffer inBuffer : ConsoleBuffer, autoScroll inAutoScroll : Bool) {
    self.mBuffer = inBuffer
    self.mAutoScroll = inAutoScroll
  }

  // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  public func makeNSView (context: Context) -> NSScrollView {
    let textView = NSTextView()
    textView.isEditable = false
    textView.isSelectable = true
    textView.isRichText = false
    textView.font = .monospacedSystemFont (ofSize: 11, weight: .regular)
    textView.textColor = .black
    textView.backgroundColor = .white
    textView.isVerticallyResizable = true
    textView.isHorizontallyResizable = false
    textView.autoresizingMask = [.width]
    textView.textContainer?.widthTracksTextView = true
    textView.textContainerInset = NSSize(width: 6, height: 6)

    let scrollView = NSScrollView()
    scrollView.documentView = textView
    scrollView.hasVerticalScroller = true
    scrollView.drawsBackground = true
    scrollView.backgroundColor = .white
    return scrollView
  }

  // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  public func updateNSView (_ nsView: NSScrollView, context: Context) {
    guard let textView = nsView.documentView as? NSTextView else { return }

    // On ne touche à la vue que si le contenu a réellement changé.
    guard textView.string.count != self.mBuffer.text.count else { return }

    let wasAtBottom = self.isScrolledToBottom (nsView)
    textView.string = self.mBuffer.text

    if self.mAutoScroll && wasAtBottom {
      textView.scrollToEndOfDocument (nil)
    }
  }

  // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  private func isScrolledToBottom (_ scrollView: NSScrollView) -> Bool {
    guard let documentView = scrollView.documentView else { return true }
    let visibleMaxY = scrollView.contentView.bounds.maxY
    let contentMaxY = documentView.bounds.maxY
    return visibleMaxY >= contentMaxY - 40 // tolérance de 40pt
  }

  // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

}

//--------------------------------------------------------------------------------------------------
// MARK: - Exemple d'utilisation

struct ConsoleDemoView: View {
    @State private var buffer = ConsoleBuffer(maxLines: 5000)

    var body: some View {
        VStack(spacing: 0) {
            ConsoleTextView(buffer: buffer, autoScroll: true)

            HStack {
                Button("Simuler 10 000 lignes") {
                    DispatchQueue.main.async {
                        for i in 0..<10_000 {
                            buffer.append("[\(i)] Ligne de log de test")
                        }
                    }
                }
                Button("Effacer") { buffer.clear() }
                Spacer()
            }
            .padding(8)
        }
        .frame(minWidth: 500, minHeight: 400)
    }
}

//--------------------------------------------------------------------------------------------------
