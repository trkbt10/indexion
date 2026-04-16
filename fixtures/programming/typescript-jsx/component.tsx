import React from 'react';

interface Props {
  name: string;
  onClick?: () => void;
}

interface ListProps {
  items: string[];
  renderItem?: (item: string, index: number) => React.ReactNode;
}

/**
 * A sample component demonstrating JSX syntax
 */
export const Component: React.FC<Props> = ({ name, onClick }) => {
  const template = `Hello, ${name}!`;

  return (
    <>
      <div className="container">
        <h1>{template}</h1>
        <button onClick={onClick}>Click me</button>
      </div>
      <SelfClosing />
      <Nested.Component prop={name} />
    </>
  );
};

/** A list component with render props. */
export function ItemList({ items, renderItem }: ListProps) {
  return (
    <ul>
      {items.map((item, i) => (
        <li key={i}>{renderItem ? renderItem(item, i) : item}</li>
      ))}
    </ul>
  );
}

/** A class-based component. */
export class Counter extends React.Component<{}, { count: number }> {
  state = { count: 0 };

  increment() {
    this.setState({ count: this.state.count + 1 });
  }

  render() {
    return <button onClick={() => this.increment()}>{this.state.count}</button>;
  }
}

// React.Fragment explicit syntax
export const WithFragment = () => (
  <React.Fragment>
    <span>First</span>
    <span>Second</span>
  </React.Fragment>
);

// Empty fragment
export const EmptyFragment = () => <></>;
