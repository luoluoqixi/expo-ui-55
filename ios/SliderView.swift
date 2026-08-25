// Copyright 2025-present 650 Industries. All rights reserved.

import SwiftUI
import ExpoModulesCore

struct SliderView: ExpoSwiftUI.View {
  @ObservedObject var props: SliderProps
  @State var value: Float = 0.0
  @State var isEditing: Bool = false
  
  init(props: SliderProps) {
    self.props = props
  }

  var body: some View {
#if !os(tvOS)
    sliderContent
      .onAppear {
        value = props.value ?? 0.0
      }
      .onChange(of: props.value) { newValue in
        if #available(iOS 26.0, *) {
          value = newValue ?? 0.0
        } else {
          guard !isEditing else { return }
          value = newValue ?? 0.0
        }
      }
      .onChange(of: value) { newValue in
        if props.value != newValue {
          props.onValueChanged([
            "value": newValue
          ])
        }
      }
#else
    Text("Slider is not supported on tvOS")
#endif
  }

#if !os(tvOS)
  @ViewBuilder
  private var sliderContent: some View {
    let label = props.children?.slot("label")
    let minimumValueLabel = props.children?.slot("minimum")
    let maximumValueLabel = props.children?.slot("maximum")
    let hasAnyLabel = label != nil || minimumValueLabel != nil || maximumValueLabel != nil

    if let min = props.min, let max = props.max, let step = props.step {
      if hasAnyLabel {
        Slider(
          value: $value,
          in: min...max,
          step: step,
          label: { label },
          minimumValueLabel: { minimumValueLabel },
          maximumValueLabel: { maximumValueLabel }
        ) { isEditing in
          self.isEditing = isEditing
          props.onEditingChanged(["isEditing": isEditing])
        }
      } else {
        Slider(
          value: $value,
          in: min...max,
          step: step
        ) { isEditing in
          self.isEditing = isEditing
          props.onEditingChanged(["isEditing": isEditing])
        }
      }
    } else if let min = props.min, let max = props.max {
      if hasAnyLabel {
        Slider(
          value: $value,
          in: min...max,
          label: { label },
          minimumValueLabel: { minimumValueLabel },
          maximumValueLabel: { maximumValueLabel }
        ) { isEditing in
          self.isEditing = isEditing
          props.onEditingChanged(["isEditing": isEditing])
        }
      } else {
        Slider(
          value: $value,
          in: min...max
        ) { isEditing in
          self.isEditing = isEditing
          props.onEditingChanged(["isEditing": isEditing])
        }
      }
    } else if let step = props.step {
      if hasAnyLabel {
        Slider(
          value: $value,
          in: 0...1,
          step: step,
          label: { label },
          minimumValueLabel: { minimumValueLabel },
          maximumValueLabel: { maximumValueLabel }
        ) { isEditing in
          self.isEditing = isEditing
          props.onEditingChanged(["isEditing": isEditing])
        }
      } else {
        Slider(
          value: $value,
          in: 0...1,
          step: step
        ) { isEditing in
          self.isEditing = isEditing
          props.onEditingChanged(["isEditing": isEditing])
        }
      }
    } else {
      if hasAnyLabel {
        Slider(
          value: $value,
          label: { label },
          minimumValueLabel: { minimumValueLabel },
          maximumValueLabel: { maximumValueLabel }
        ) { isEditing in
          self.isEditing = isEditing
          props.onEditingChanged(["isEditing": isEditing])
        }
      } else {
        Slider(value: $value) { isEditing in
          self.isEditing = isEditing
          props.onEditingChanged(["isEditing": isEditing])
        }
      }
    }
  }
#endif
}

final class SliderProps: UIBaseViewProps {
  @Field var value: Float?
  @Field var step: Float?
  @Field var min: Float?
  @Field var max: Float?
  var onValueChanged = EventDispatcher()
  var onEditingChanged = EventDispatcher()
}

