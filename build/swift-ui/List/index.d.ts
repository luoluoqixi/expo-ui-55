import { ListForEach, type ListForEachProps } from './ListForEach';
import { type CommonViewModifierProps } from '../types';
export interface ListProps extends CommonViewModifierProps {
    /**
     * Whether UIKit automatically adjusts the native scroll indicator insets.
     * @default true
     */
    automaticallyAdjustsScrollIndicatorInsets?: boolean;
    /**
     * How UIKit adjusts the native list's content insets for navigation bars and safe areas.
     * @default 'automatic'
     */
    contentInsetAdjustmentBehavior?: 'automatic' | 'scrollableAxes' | 'never' | 'always';
    /**
     * Shrinks the list viewport when its host extends below the physical screen boundary.
     * Useful for native sheet containers that clip hosted SwiftUI content at smaller detents.
     * @default false
     */
    compensatesForViewportClipping?: boolean;
    /**
     * Corrects a cached safe-area offset in a nested List's private scroll-indicator track.
     * This is opt-in; callers are responsible for platform and OS-version gating.
     * @default false
     */
    correctsNestedScrollIndicatorFrame?: boolean;
    /**
     * Dismisses the current keyboard when a non-text-input area of the native list is tapped.
     * The native recognizer does not cancel child control touches.
     * @default false
     */
    dismissKeyboardOnTap?: boolean;
    /**
     * The anchor used when scrolling to `initialScrollTarget`.
     * @default 'center'
     */
    initialScrollAnchor?: 'zero' | 'topLeading' | 'top' | 'topTrailing' | 'leading' | 'center' | 'trailing' | 'bottomLeading' | 'bottom' | 'bottomTrailing';
    /**
     * The child identity to scroll into view after the list mounts.
     * Children should use the `viewID` modifier with the same value.
     */
    initialScrollTarget?: string | number;
    /**
     * The native edit state used by List selection controls.
     * @default 'inactive'
     */
    nativeEditMode?: 'active' | 'inactive' | 'transient';
    /**
     * Tint used by native List selection controls while editing.
     */
    nativeEditTint?: string;
    /**
     * Whether the native refresh control accepts pull-to-refresh gestures.
     * @default true
     */
    refreshEnabled?: boolean;
    /** Whether the List installs its stable native refresh control. */
    refreshable?: boolean;
    /** Whether the native refresh indicator is active. */
    refreshing?: boolean;
    /** Called when the native refresh control is triggered. */
    onRefresh?: () => void;
    /**
     * Requests restoration of the native list's last recorded scroll offset.
     * Increment this after a state transition that causes SwiftUI List to reset its offset.
     */
    scrollPositionRestoreToken?: number;
    /**
     * Registers the backing native list as the current view controller's top content scroll view.
     * This lets UIKit drive navigation-bar scroll-edge appearance changes without JS scroll events.
     * @default false
     */
    tracksNavigationBarScrollEdge?: boolean;
    /**
     * The children elements to be rendered inside the list.
     */
    children: React.ReactNode;
    /**
     * The currently selected item tags.
     */
    selection?: (string | number)[];
    /**
     * Callback triggered when the selection changes in a list.
     * Returns an array of selected item tags.
     */
    onSelectionChange?: (selection: (string | number)[]) => void;
}
/**
 * A list component that renders its children using a native SwiftUI `List`.
 */
export declare function List(props: ListProps): import("react").JSX.Element;
export declare namespace List {
    var ForEach: typeof ListForEach;
}
export { ListForEach, ListForEachProps };
//# sourceMappingURL=index.d.ts.map