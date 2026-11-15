#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

void *yoru_torrent_create(int isolated);
void yoru_torrent_destroy(void *engine);
char *yoru_torrent_add(void *engine, const uint8_t *torrent, size_t torrent_size,
    const uint8_t *resume, size_t resume_size, const char *name, const char *id,
    const char *folder, const char *resume_file, const int32_t *selection, size_t selected,
    size_t expected_files, int paused);
char *yoru_torrent_status(void *engine);
char *yoru_torrent_files(void *engine, const char *id);
char *yoru_torrent_action(void *engine, const char *id, int start);
void yoru_torrent_save(void *engine);
void yoru_torrent_remove(void *engine, const char *id);
char *yoru_torrent_peer(void *engine, const char *id, const char *address, uint16_t port);
uint16_t yoru_torrent_port(void *engine);

#ifdef __cplusplus
}
#endif
