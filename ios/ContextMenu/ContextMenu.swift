import SwiftUI
import ExpoModulesCore

#if os(iOS)
import UIKit

private final class ContextMenuInteractionGateView: UIView {
  var contextMenuEnabled = true {
    didSet {
      scheduleInteractionUpdate()
    }
  }

  private weak var hostView: UIView?
  private var contextMenuInteraction: UIContextMenuInteraction?

  override init(frame: CGRect) {
    super.init(frame: frame)
    isHidden = true
    isUserInteractionEnabled = false
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func didMoveToSuperview() {
    super.didMoveToSuperview()
    scheduleInteractionUpdate()
  }

  override func didMoveToWindow() {
    super.didMoveToWindow()
    if window == nil {
      restoreInteraction()
    } else {
      scheduleInteractionUpdate()
    }
  }

  func scheduleInteractionUpdate() {
    updateInteraction()
    DispatchQueue.main.async { [weak self] in self?.updateInteraction() }
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in self?.updateInteraction() }
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in self?.updateInteraction() }
  }

  func restoreInteraction() {
    guard
      let hostView,
      let contextMenuInteraction,
      !hostView.interactions.contains(where: { $0 === contextMenuInteraction })
    else {
      return
    }
    hostView.addInteraction(contextMenuInteraction)
  }

  private func updateInteraction() {
    if let next = contextMenuHost() {
      if hostView !== next.hostView || contextMenuInteraction !== next.interaction {
        restoreInteraction()
        hostView = next.hostView
        contextMenuInteraction = next.interaction
      }
    }

    guard let hostView, let contextMenuInteraction else { return }
    if contextMenuEnabled {
      restoreInteraction()
    } else if hostView.interactions.contains(where: { $0 === contextMenuInteraction }) {
      hostView.removeInteraction(contextMenuInteraction)
    }
  }

  private func contextMenuHost() -> (hostView: UIView, interaction: UIContextMenuInteraction)? {
    var candidate = superview
    while let view = candidate {
      if let interaction = view.interactions.first(where: { $0 is UIContextMenuInteraction })
        as? UIContextMenuInteraction {
        return (view, interaction)
      }
      candidate = view.superview
    }
    return nil
  }
}

private struct ContextMenuInteractionGate: UIViewRepresentable {
  let enabled: Bool

  func makeUIView(context: Context) -> ContextMenuInteractionGateView {
    let view = ContextMenuInteractionGateView()
    view.contextMenuEnabled = enabled
    return view
  }

  func updateUIView(_ uiView: ContextMenuInteractionGateView, context: Context) {
    uiView.contextMenuEnabled = enabled
  }

  static func dismantleUIView(_ uiView: ContextMenuInteractionGateView, coordinator: Void) {
    uiView.restoreInteraction()
  }
}
#endif

private extension View {
  @ViewBuilder
  func contextMenuInteractionGate(enabled: Bool) -> some View {
#if os(iOS)
    background(ContextMenuInteractionGate(enabled: enabled))
#else
    self
#endif
  }
}

struct ContextMenuWithPreview<ActivationElement: View, Preview: View, MenuContent: View>: View {
  let activationElement: ActivationElement
  let enabled: Bool
  let preview: Preview
  let menuContent: MenuContent

  var body: some View {
    if #available(iOS 16.0, tvOS 16.0, *) {
      activationElement.contextMenuInteractionGate(enabled: enabled).contextMenu(menuItems: {
        if enabled {
          menuContent
        }
      }, preview: {
        preview
      })
    } else {
      activationElement.contextMenuInteractionGate(enabled: enabled).contextMenu(menuItems: {
        if enabled {
          menuContent
        }
      })
    }
  }
}

internal struct LongPressContextMenu<ActivationElement: View, MenuContent: View>: View {
  let activationElement: ActivationElement
  let enabled: Bool
  let menuContent: MenuContent

  var body: some View {
    activationElement.contextMenuInteractionGate(enabled: enabled).contextMenu(menuItems: {
      if enabled {
        menuContent
      }
    })
  }
}

struct ContextMenu: ExpoSwiftUI.View {
  @ObservedObject var props: ContextMenuProps

  var body: some View {
    let activationElement = props.children?.slot("trigger")
    let menuContent = props.children?.slot("items")
    let preview = props.children?.slot("preview")

    if let activationElement {
      if let preview {
        ContextMenuWithPreview(
          activationElement: activationElement,
          enabled: props.enabled,
          preview: preview,
          menuContent: menuContent
        )
      } else {
        LongPressContextMenu(
          activationElement: activationElement,
          enabled: props.enabled,
          menuContent: menuContent
        )
      }
    }
  }
}
