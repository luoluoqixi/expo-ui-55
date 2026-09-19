// Copyright 2025-present 650 Industries. All rights reserved.

import SwiftUI
import ExpoModulesCore

public enum ButtonRole: String, Enumerable {
  case `default`
  case destructive
  case cancel

  public func toNativeRole() -> SwiftUI.ButtonRole? {
    switch self {
    case .default:
      return nil
    case .destructive:
      return SwiftUI.ButtonRole.destructive
    case .cancel:
      return SwiftUI.ButtonRole.cancel
    }
  }
}

open class ButtonProps: UIBaseViewProps, Observable {
  @Field public var label: String?
  @Field public var systemImage: String?
  @Field public var role: ButtonRole?
  /// When rendered inside a List, immediately writes this tag to that List's
  /// selection binding before dispatching the press event to JS.
  @Field public var listSelectionId: Either<String, Double>?
  var onButtonPress = EventDispatcher()
}
