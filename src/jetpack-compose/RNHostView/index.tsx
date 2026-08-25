import { requireNativeView } from 'expo';
import React from 'react';

import { type ModifierConfig } from '../../types';
import { PrimitiveBaseProps } from '../layout';
import { createViewModifierEventListener } from '../modifiers/utils';

export interface RNHostProps extends PrimitiveBaseProps {
  /**
   * When `true`, the RNHost will update its size in the Jetpack Compose view tree to match the children's size.
   * When `false`, the RNHost will use the size of the parent Jetpack Compose View.
   * Can be only set once on mount.
   * @default false
   */
  matchContents?: boolean | { vertical?: boolean; horizontal?: boolean };
  /**
   * The RN View to be hosted.
   */
  children: React.ReactElement;
  /**
   * Modifiers for the component.
   */
  modifiers?: ModifierConfig[];
}

type NativeRNHostProps = Omit<RNHostProps, 'matchContents'> & {
  matchContentsHorizontal?: boolean;
  matchContentsVertical?: boolean;
};
const NativeRNHostView: React.ComponentType<NativeRNHostProps> = requireNativeView(
  'ExpoUI',
  'RNHostView'
);

function transformProps(props: RNHostProps): NativeRNHostProps {
  const { matchContents, modifiers, ...restProps } = props;
  const matchContentsVertical =
    typeof matchContents === 'object' ? matchContents.vertical : matchContents;
  const matchContentsHorizontal =
    typeof matchContents === 'object' ? matchContents.horizontal : matchContents;

  return {
    modifiers,
    ...(modifiers ? createViewModifierEventListener(modifiers) : undefined),
    matchContentsHorizontal,
    matchContentsVertical,
    ...restProps,
  };
}

export function RNHostView(props: RNHostProps) {
  const matchContentsVertical =
    typeof props.matchContents === 'object' ? props.matchContents.vertical : props.matchContents;
  const matchContentsHorizontal =
    typeof props.matchContents === 'object'
      ? props.matchContents.horizontal
      : props.matchContents;

  return (
    <NativeRNHostView
      {...transformProps(props)}
      // `matchContents` can only be used once on mount
      // So we force unmount when it changes to prevent unexpected layout
      key={`matchContents:${matchContentsHorizontal ? '1' : '0'}:${matchContentsVertical ? '1' : '0'}`}
    />
  );
}
