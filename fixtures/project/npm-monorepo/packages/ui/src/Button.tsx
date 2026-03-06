import React from 'react';
import { createId } from '@example/core';
import type { ButtonProps } from './types';

export function Button({ children, onClick }: ButtonProps) {
  const id = createId();
  return (
    <button id={id} onClick={onClick}>
      {children}
    </button>
  );
}
