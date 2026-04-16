import React from 'react';

/**
 * A sample component demonstrating JSX syntax
 */
export const Component = ({ name, onClick }) => {
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
export function ItemList({ items, renderItem }) {
  return (
    <ul>
      {items.map((item, i) => (
        <li key={i}>{renderItem ? renderItem(item, i) : item}</li>
      ))}
    </ul>
  );
}

/** A class-based component with state. */
export class TodoApp extends React.Component {
  constructor(props) {
    super(props);
    this.state = { items: [], text: '' };
  }

  handleChange(e) {
    this.setState({ text: e.target.value });
  }

  handleSubmit(e) {
    e.preventDefault();
    const item = { text: this.state.text, id: Date.now() };
    this.setState({ items: [...this.state.items, item], text: '' });
  }

  render() {
    return (
      <div>
        <h3>TODO</h3>
        <ul>
          {this.state.items.map(item => (
            <li key={item.id}>{item.text}</li>
          ))}
        </ul>
        <form onSubmit={(e) => this.handleSubmit(e)}>
          <input onChange={(e) => this.handleChange(e)} value={this.state.text} />
          <button>Add</button>
        </form>
      </div>
    );
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
