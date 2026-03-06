import React from 'react';
import clsx from 'clsx';
import type { ButtonProps } from '../types';

export function Button({ variant = 'primary', size = 'md', onClick, children }: ButtonProps) {
  const className = clsx(
    'btn',
    `btn-${variant}`,
    `btn-${size}`
  );

  return (
    <button className={className} onClick={onClick}>
      {children}
    </button>
  );
}
