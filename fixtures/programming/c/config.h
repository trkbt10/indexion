/**
 * Configuration loader — public C interface.
 */
#ifndef CONFIG_H
#define CONFIG_H

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

/** A configuration entry. */
typedef struct ConfigEntry {
    char key[256];
    char value[256];
} ConfigEntry;

/** Loads configuration entries from a file. Returns the count. */
int config_load(int max_entries);

/** Retrieves a config value by index. */
int config_get(int index);

#ifdef __cplusplus
}
#endif

#endif /* CONFIG_H */
