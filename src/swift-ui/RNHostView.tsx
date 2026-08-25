import { requireNativeView } from 'expo';

const RNHostNativeView: React.ComponentType<any> = requireNativeView('ExpoUI', 'RNHostView');

export type RNHostViewProps = {
  /**
   * When `true`, the RNHost will update its size in the React Native view tree to match the children's size.
   * When `false`, the RNHost will use the size of the parent SwiftUI View.
   * Can be only set once on mount.
   * @default false
   */
  matchContents?: boolean | { vertical?: boolean; horizontal?: boolean };
  /**
   * The RN View to be hosted.
   */
  children: React.ReactElement;
};

export function RNHostView(props: RNHostViewProps) {
  const { matchContents, ...restProps } = props;
  const matchContentsVertical =
    typeof matchContents === 'object' ? matchContents.vertical : matchContents;
  const matchContentsHorizontal =
    typeof matchContents === 'object' ? matchContents.horizontal : matchContents;

  return (
    <RNHostNativeView
      {...restProps}
      matchContentsHorizontal={matchContentsHorizontal}
      matchContentsVertical={matchContentsVertical}
      // `matchContents` can only be used once on mount
      // So we force unmount when it changes to prevent unexpected layout
      key={`matchContents:${matchContentsHorizontal ? '1' : '0'}:${matchContentsVertical ? '1' : '0'}`}
    />
  );
}
