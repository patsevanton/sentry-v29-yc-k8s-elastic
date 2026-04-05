/* Минимальный нативный пример: ELF + DWARF для sentry-cli debug-files upload (Linux). */
#include <stdio.h>

static int answer(void) { return 42; }

int main(void) {
  printf("ok %d\n", answer());
  return 0;
}
