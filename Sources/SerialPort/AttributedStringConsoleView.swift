//--------------------------------------------------------------------------------------------------
//  Created by Pierre Molinaro on 13/08/2026.
//--------------------------------------------------------------------------------------------------

import SwiftUI
import Combine

//--------------------------------------------------------------------------------------------------

/// Vue console basée sur NSTextView : les mises à jour arrivent par un flux
/// Combine et sont appliquées par append/delete incrémental sur le
/// NSTextStorage, en contournant le cycle de diff SwiftUI (trop coûteux
/// pour du texte attribué qui grossit en continu).
public struct AttributedConsoleView : NSViewRepresentable {

  // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  @State private var mBuffer : AttributedStringBuffer
  private var mAutoScroll : Bool = true
  private var maxLines : Int = 5000

  // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  public init (buffer inBuffer : AttributedStringBuffer, autoScroll inAutoScroll : Bool) {
    self.mBuffer = inBuffer
    self.mAutoScroll = inAutoScroll
  }

  // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  public func makeCoordinator() -> AttributedConsoleViewCoordinator {
    AttributedConsoleViewCoordinator (maxLines: self.maxLines, autoScroll: self.mAutoScroll)
  }

  // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  public func makeNSView (context: Context) -> NSScrollView {
    let textView = NSTextView()
    textView.isEditable = false
    textView.isSelectable = true
    textView.isRichText = true
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

    context.coordinator.textView = textView
    context.coordinator.scrollView = scrollView
    context.coordinator.subscribe (to: self.mBuffer)

    return scrollView
  }

  // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  public func updateNSView(_ nsView: NSScrollView, context: Context) {
      // Volontairement vide : les mises à jour passent par le subscriber
      // Combine du Coordinator, pas par le diff SwiftUI classique.
  }

  // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
}

//--------------------------------------------------------------------------------------------------

@MainActor public final class AttributedConsoleViewCoordinator {

  // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  weak var textView: NSTextView?
  weak var scrollView: NSScrollView?
  private var cancellables = Set<AnyCancellable>()
  private let maxLines: Int
  private let autoScroll: Bool
  private var lineCount = 0

  // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  init(maxLines: Int, autoScroll: Bool) {
    self.maxLines = maxLines
    self.autoScroll = autoScroll
  }

  // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  func subscribe (to inBuffer : AttributedStringBuffer) {
    inBuffer.appended
    .sink { [weak self] chunk in self?.appendChunk(chunk) }
    .store(in: &cancellables)

    inBuffer.cleared
      .sink { [weak self] in self?.clearAll() }
      .store(in: &cancellables)
  }

  // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  private func appendChunk(_ inString : String) {
      guard let textView, let scrollView, let storage = textView.textStorage else { return }

      let wasAtBottom = isScrolledToBottom(scrollView)
      let chunk = NSAttributedString(string: inString)
      storage.beginEditing()
      storage.append(chunk)
      storage.endEditing()

      lineCount += chunk.string.reduce(0) { $1 == "\n" ? $0 + 1 : $0 }

      if lineCount > maxLines {
          trimExcess(storage)
      }

      if autoScroll && wasAtBottom {
          textView.scrollToEndOfDocument(nil)
      }
  }

  // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  /// Supprime les plus anciennes lignes en dépassement, par suppression
  /// de plage en tête de texte (pas de reconstruction complète).
  private func trimExcess(_ storage: NSTextStorage) {
      let excess = lineCount - maxLines
      let full = storage.string as NSString
      var searchStart = 0
      var newlinesFound = 0
      while newlinesFound < excess {
          let range = full.range(of: "\n", range: NSRange(location: searchStart, length: full.length - searchStart))
          guard range.location != NSNotFound else { break }
          searchStart = range.location + 1
          newlinesFound += 1
      }
      if searchStart > 0 {
          storage.beginEditing()
          storage.deleteCharacters(in: NSRange(location: 0, length: searchStart))
          storage.endEditing()
          lineCount -= newlinesFound
      }
  }

  // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  private func clearAll() {
      textView?.textStorage?.setAttributedString(NSAttributedString(string: ""))
      lineCount = 0
  }

  // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  private func isScrolledToBottom(_ scrollView: NSScrollView) -> Bool {
      guard let documentView = scrollView.documentView else { return true }
      let visibleMaxY = scrollView.contentView.bounds.maxY
      let contentMaxY = documentView.bounds.maxY
      return visibleMaxY >= contentMaxY - 40 // tolérance
  }

  // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

}

//--------------------------------------------------------------------------------------------------
