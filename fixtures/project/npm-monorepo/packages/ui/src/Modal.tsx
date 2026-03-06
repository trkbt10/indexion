import React from 'react';
import { Button } from './Button';
import type { ModalProps } from './types';

export function Modal({ title, onClose, children }: ModalProps) {
  return (
    <div className="modal">
      <header>
        <h2>{title}</h2>
        <Button onClick={onClose}>×</Button>
      </header>
      <div className="modal-body">{children}</div>
    </div>
  );
}
