/**
 * Мини-бандл для демонстрации: после минификации стек указывает на app.js;
 * с загруженными source maps Sentry восстановит имена из этого файла.
 */
function inner() {
  throw new Error("demo: source-mapped stack");
}

export function runDemo() {
  inner();
}
