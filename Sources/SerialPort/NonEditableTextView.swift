//--------------------------------------------------------------------------------------------------

import SwiftUI

//--------------------------------------------------------------------------------------------------

public struct NonEditableTextView : View {

  // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  private let mAttributedString : AttributedString
  private let mAutoScroll : Bool
  @State private var mScrollToBottomID = UUID ()

  // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  public init (attributedString inAttributedString : AttributedString,
        autoScroll inAutoScroll : Bool) {
    self.mAttributedString = inAttributedString
    self.mAutoScroll = inAutoScroll
  }

  // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  public var body : some View {
    ScrollViewReader { readyProxy in
      ScrollView {
        Text (self.mAttributedString)
        .textSelection (.enabled)
        .frame (maxWidth: .infinity, alignment: .leading)
        .id (self.mScrollToBottomID) // unique pour chaque mise à jour
        .frame (maxWidth: .infinity, alignment: .leading)
      }
      .background (Rectangle().fill(.quinary)) //black.opacity (0.025))
      .onChange (of: self.mAutoScroll) {
        if self.mAutoScroll {
          readyProxy.scrollTo (self.mScrollToBottomID, anchor: .bottom)
        }
      }
      .onChange (of: self.mAttributedString) {
        if mAutoScroll {
          Task { @MainActor in
            readyProxy.scrollTo (self.mScrollToBottomID, anchor: .bottom)
          }
        }
      }
    }
  }

  // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

}

//--------------------------------------------------------------------------------------------------
