// Copyright 2015-present 650 Industries. All rights reserved.

import SwiftUI
import ExpoModulesCore

internal final class RNHostViewProps: ExpoSwiftUI.ViewProps {
  @Field var matchContents: Bool?
  @Field var matchContentsHorizontal: Bool?
  @Field var matchContentsVertical: Bool?
}

struct RNHostView: ExpoSwiftUI.View {
  
  @ObservedObject var props: RNHostViewProps

  var body: some View {
    let matchContentsHorizontal = props.matchContentsHorizontal ?? props.matchContents ?? false
    let matchContentsVertical = props.matchContentsVertical ?? props.matchContents ?? false

    if (matchContentsHorizontal || matchContentsVertical), let childUIView = firstChildUIView {
      ApplySizeFromYogaNode(
        childUIView: childUIView,
        shadowNodeProxy: props.shadowNodeProxy,
        matchContentsHorizontal: matchContentsHorizontal,
        matchContentsVertical: matchContentsVertical
      ) {
        Children()
      }
      .onAppear {
        ExpoUITouchHandlerHelper.createAndAttachTouchHandler(for: childUIView)
      }
    } else {
      Children()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .modifier(
          ReportSizeToYogaNodeModifier(
            shadowNodeProxy: props.shadowNodeProxy
          )
        )
        .onAppear {
          if let view = firstChildUIView {
            ExpoUITouchHandlerHelper.createAndAttachTouchHandler(for: view)
          }
        }
    }
  }

  private var firstChildUIView: UIView? {
    props.children?.first?.uiView
  }
}

// Sets SwiftUI view size from Yoga node size
// Listens to Yoga node size changes and updates the SwiftUI view size
private struct ApplySizeFromYogaNode<Content: SwiftUI.View>: SwiftUI.View {
  @StateObject private var observer: Observer
  let shadowNodeProxy: ExpoSwiftUI.ShadowNodeProxy
  let matchContentsHorizontal: Bool
  let matchContentsVertical: Bool
  let content: Content

  init(
    childUIView: UIView,
    shadowNodeProxy: ExpoSwiftUI.ShadowNodeProxy,
    matchContentsHorizontal: Bool,
    matchContentsVertical: Bool,
    @ViewBuilder content: () -> Content
  ) {
    _observer = StateObject(wrappedValue: Observer(view: childUIView))
    self.shadowNodeProxy = shadowNodeProxy
    self.matchContentsHorizontal = matchContentsHorizontal
    self.matchContentsVertical = matchContentsVertical
    self.content = content()
  }

  var body: some SwiftUI.View {
    content
      .frame(
        maxWidth: matchContentsHorizontal ? nil : .infinity,
        maxHeight: matchContentsVertical ? nil : .infinity,
        alignment: .topLeading
      )
      .frame(
        width: matchContentsHorizontal ? observer.size.width : nil,
        height: matchContentsVertical ? observer.size.height : nil,
        alignment: .topLeading
      )
      .modifier(
        ReportSizeToYogaNodeModifier(
          shadowNodeProxy: shadowNodeProxy,
          reportHorizontal: !matchContentsHorizontal,
          reportVertical: !matchContentsVertical
        )
      )
  }

  @MainActor
  fileprivate class Observer: ObservableObject {
    @Published var size: CGSize
    private var kvoToken: NSKeyValueObservation?

    init(view: UIView) {
      self.size = view.bounds.size
      kvoToken = view.observe(\.bounds) { [weak self] view, _ in
        MainActor.assumeIsolated {
          self?.size = view.bounds.size
        }
      }
    }

    deinit {
      kvoToken?.invalidate()
    }
  }
}

// Sets Yoga node size from SwiftUI view size
// Listens to SwiftUI view size changes and updates the Yoga node size
private struct ReportSizeToYogaNodeModifier: ViewModifier {
  let shadowNodeProxy: ExpoSwiftUI.ShadowNodeProxy
  let reportHorizontal: Bool
  let reportVertical: Bool

  init(
    shadowNodeProxy: ExpoSwiftUI.ShadowNodeProxy,
    reportHorizontal: Bool = true,
    reportVertical: Bool = true
  ) {
    self.shadowNodeProxy = shadowNodeProxy
    self.reportHorizontal = reportHorizontal
    self.reportVertical = reportVertical
  }

  private func handleSizeChange(_ size: CGSize) {
    shadowNodeProxy.setViewSize?(
      CGSize(
        width: reportHorizontal ? size.width : CGFloat.nan,
        height: reportVertical ? size.height : CGFloat.nan
      )
    )
  }

  func body(content: Content) -> some View {
    if #available(iOS 16.0, tvOS 16.0, macOS 13.0, *) {
      content.onGeometryChange(for: CGSize.self, of: { proxy in proxy.size }) { size in
        handleSizeChange(size)
      }
    } else {
      content.overlay {
        GeometryReader { geometry in
          Color.clear
            .hidden()
            .onAppear {
              handleSizeChange(geometry.size)
            }
            .onChange(of: geometry.size) { handleSizeChange($0) }
        }
      }
    }
  }
}
