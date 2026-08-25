// Copyright 2015-present 650 Industries. All rights reserved.

import ExpoModulesCore
import SwiftUI

internal enum AxisSetType: String, Enumerable {
  case both
  case horizontal
  case vertical
  
  func toAxis() -> SwiftUI.Axis.Set {
    switch self {
    case .horizontal:
        .horizontal
    case .vertical:
        .vertical
    case .both:
        [.horizontal, .vertical]
    }
  }
}

internal struct ContainerRelativeFrameModifier: ViewModifier, Record {
  @Field var axes: AxisSetType = .both
  @Field var count: Int = 0
  @Field var span: Int = 1
  @Field var spacing: CGFloat = 0
  @Field var alignment: AlignmentOptions = .center

  @ViewBuilder
  func body(content: Content) -> some View {
    if #available(iOS 17.0, tvOS 17.0, *) {
      if count > 0 {
        content.containerRelativeFrame(axes.toAxis(), count: count, span: span, spacing: spacing, alignment: alignment.toAlignment())
      } else {
        content.containerRelativeFrame(axes.toAxis(), alignment: alignment.toAlignment())
      }
    } else {
      content
    }
  }
}

internal enum ContentMarginPlacementType: String, Enumerable {
  case automatic
  case scrollContent
  case scrollIndicators

  @available(iOS 17.0, tvOS 17.0, macOS 14.0, watchOS 10.0, *)
  func toSwiftUI() -> SwiftUI.ContentMarginPlacement {
    switch self {
    case .scrollContent:
      return .scrollContent
    case .scrollIndicators:
      return .scrollIndicators
    case .automatic:
      return .automatic
    }
  }
}

internal struct ContentMarginsModifier: ViewModifier, Record {
  @Field var edges: EdgeOptions = .all
  @Field var length: CGFloat?
  @Field var placement: ContentMarginPlacementType = .automatic

  @ViewBuilder
  func body(content: Content) -> some View {
    if #available(iOS 17.0, tvOS 17.0, macOS 14.0, watchOS 10.0, *) {
      content.contentMargins(edges.toEdge(), length, for: placement.toSwiftUI())
    } else {
      content
    }
  }
}
