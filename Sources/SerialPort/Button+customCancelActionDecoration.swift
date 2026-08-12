//--------------------------------------------------------------------------------------------------
//  Created by Pierre Molinaro on 22/03/2026.
//--------------------------------------------------------------------------------------------------

import SwiftUI

//--------------------------------------------------------------------------------------------------

extension Button {

  // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  @ViewBuilder func customCancelActionDecoration (disabled inDisabled : Bool = false) -> some View {
    if inDisabled {
      self.disabled (true)
    }else{
      self
      .keyboardShortcut (.cancelAction)
      .overlay (RoundedRectangle (cornerRadius: 6).stroke (.purple, lineWidth: 1.5))
    }
  }

  // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

}

//--------------------------------------------------------------------------------------------------
