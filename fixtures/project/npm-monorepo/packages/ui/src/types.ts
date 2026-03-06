import type { ReactNode } from 'react';

export interface ButtonProps {
  children: ReactNode;
  onClick?: () => void;
}

export interface ModalProps {
  title: string;
  onClose: () => void;
  children: ReactNode;
}
