import React, { useState } from 'react';
import { deepMerge } from '@example/core';
import { Button, Modal } from '@example/ui';

interface AppState {
  showModal: boolean;
}

export function App() {
  const [state, setState] = useState<AppState>({ showModal: false });

  const updateState = (partial: Partial<AppState>) => {
    setState(prev => deepMerge(prev, partial));
  };

  return (
    <div>
      <h1>Example App</h1>
      <Button onClick={() => updateState({ showModal: true })}>
        Open Modal
      </Button>
      {state.showModal && (
        <Modal title="Hello" onClose={() => updateState({ showModal: false })}>
          <p>This is the modal content.</p>
        </Modal>
      )}
    </div>
  );
}
