// Gnotchi Bridging-Header (0.8.0, G32): minimale Deklarationen aus libarchive 3.x (archive.h/archive_entry.h,
// BSD-2-Clause). Das macOS-SDK liefert `libarchive.tbd`, aber keinen Header – nur, was ShelfZip braucht.
#include <sys/types.h>
#include <stdint.h>
struct archive; struct archive_entry;
struct archive *archive_write_new(void);
int archive_write_set_format_zip(struct archive *);
int archive_write_set_options(struct archive *, const char *);
int archive_write_set_passphrase(struct archive *, const char *);
int archive_write_open_filename(struct archive *, const char *);
int archive_write_header(struct archive *, struct archive_entry *);
ssize_t archive_write_data(struct archive *, const void *, size_t);
int archive_write_finish_entry(struct archive *);
int archive_write_close(struct archive *);
int archive_write_free(struct archive *);
const char *archive_error_string(struct archive *);
struct archive_entry *archive_entry_new(void);
void archive_entry_free(struct archive_entry *);
void archive_entry_set_pathname_utf8(struct archive_entry *, const char *);
void archive_entry_set_size(struct archive_entry *, int64_t);
void archive_entry_set_filetype(struct archive_entry *, unsigned int);
void archive_entry_set_perm(struct archive_entry *, unsigned short);
void archive_entry_set_mtime(struct archive_entry *, time_t, long);
