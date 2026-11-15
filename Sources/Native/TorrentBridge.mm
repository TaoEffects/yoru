#import <Foundation/Foundation.h>
#include "TorrentBridge.h"
#include <libtorrent/add_torrent_params.hpp>
#include <libtorrent/alert_types.hpp>
#include <libtorrent/read_resume_data.hpp>
#include <libtorrent/session.hpp>
#include <libtorrent/settings_pack.hpp>
#include <libtorrent/torrent_info.hpp>
#include <libtorrent/write_resume_data.hpp>
#include <algorithm>
#include <chrono>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <map>
#include <thread>

namespace lt = libtorrent;
namespace {

NSString *text(std::string const& value) {
    return [[NSString alloc] initWithBytes:value.data() length:value.size() encoding:NSUTF8StringEncoding] ?: @"";
}

char *json(id value) {
    NSData *data = [NSJSONSerialization dataWithJSONObject:value options:0 error:nil];
    NSString *result = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    return strdup(result ? result.UTF8String : "[]");
}

char *failure(const char *message) { return strdup(message); }

lt::settings_pack settings(bool isolated) {
    lt::settings_pack result;
    result.set_str(lt::settings_pack::user_agent, "Yoru/0.5 (libtorrent)");
    result.set_int(lt::settings_pack::alert_mask, lt::alert_category::storage | lt::alert_category::error);
    result.set_str(lt::settings_pack::listen_interfaces, isolated ? "127.0.0.1:0" : "0.0.0.0:0,[::]:0");
    result.set_bool(lt::settings_pack::enable_upnp, false);
    result.set_bool(lt::settings_pack::enable_natpmp, false);
    if (isolated) {
        result.set_bool(lt::settings_pack::enable_dht, false);
        result.set_bool(lt::settings_pack::enable_lsd, false);
    }
    return result;
}

struct Entry {
    std::string name;
    std::string folder;
    std::string resume;
    lt::torrent_handle handle;
    bool complete = false;
};

struct Engine {
    lt::session session;
    std::map<std::string, Entry> entries;
    std::chrono::steady_clock::time_point last_save{};
    size_t pending = 0;

    explicit Engine(bool isolated) : session(settings(isolated)) {}

    void drain() {
        std::vector<lt::alert*> alerts;
        session.pop_alerts(&alerts);
        for (auto const *alert : alerts) {
            if (auto const *saved = lt::alert_cast<lt::save_resume_data_alert>(alert)) {
                if (pending > 0) --pending;
                for (auto const& [_, entry] : entries) {
                    if (entry.handle != saved->handle) continue;
                    auto const bytes = lt::write_resume_data_buf(saved->params);
                    NSData *data = [NSData dataWithBytes:bytes.data() length:bytes.size()];
                    [data writeToFile:text(entry.resume) options:NSDataWritingAtomic error:nil];
                    break;
                }
            } else if (lt::alert_cast<lt::save_resume_data_failed_alert>(alert) && pending > 0) {
                --pending;
            }
        }
    }

    void save(bool wait) {
        drain();
        for (auto const& [_, entry] : entries) {
            entry.handle.save_resume_data();
            ++pending;
        }
        last_save = std::chrono::steady_clock::now();
        if (!wait) return;
        const auto until = last_save + std::chrono::milliseconds(1600);
        while (pending > 0 && std::chrono::steady_clock::now() < until) {
            session.wait_for_alert(std::chrono::milliseconds(30));
            drain();
        }
    }
};

const char *state(lt::torrent_status const& status) {
    if (status.errc) return "error";
    if (status.is_finished) return "complete";
    if (status.flags & lt::torrent_flags::paused) return "paused";
    if (status.state == lt::torrent_status::checking_files || status.state == lt::torrent_status::checking_resume_data) return "checking";
    if (status.download_rate == 0) return "stalled";
    return "downloading";
}

} // namespace

void *yoru_torrent_create(int isolated) {
    try { return new Engine(isolated != 0); } catch (...) { return nullptr; }
}

void yoru_torrent_destroy(void *opaque) {
    if (!opaque) return;
    auto *engine = static_cast<Engine *>(opaque);
    try { engine->save(true); } catch (...) {}
    delete engine;
}

char *yoru_torrent_add(void *opaque, const uint8_t *torrent, size_t torrent_size,
    const uint8_t *resume, size_t resume_size, const char *name, const char *id,
    const char *folder, const char *resume_file, const int32_t *selection, size_t selected,
    size_t expected_files, int paused) {
    @autoreleasepool {
        auto& engine = *static_cast<Engine *>(opaque);
        if (engine.entries.contains(id)) return failure("Ce torrent est déjà dans Yoru.");
        try {
            lt::error_code error;
            const lt::span<char const> buffer(reinterpret_cast<char const *>(torrent), torrent_size);
            auto info = std::make_shared<lt::torrent_info>(buffer, error, lt::from_span);
            if (error) return failure(error.message().c_str());
            auto const& files = info->files();
            if (static_cast<size_t>(files.num_files()) != expected_files) return failure("Liste des fichiers incohérente.");
            for (auto i : files.file_range()) {
                if (files.file_flags(i) & lt::file_storage::flag_symlink) return failure("Le torrent contient un lien symbolique.");
            }
            lt::add_torrent_params params;
            if (resume_size > 0) {
                auto resumed = lt::read_resume_data(lt::span<char const>(reinterpret_cast<char const *>(resume), resume_size), error);
                if (!error && resumed.info_hashes == info->info_hashes()) params = std::move(resumed);
                error.clear();
            }
            params.ti = std::move(info);
            params.save_path = folder;
            params.renamed_files.clear();
            params.trackers.clear();
            params.flags &= ~(lt::torrent_flags::override_trackers | lt::torrent_flags::override_web_seeds
                | lt::torrent_flags::auto_managed | lt::torrent_flags::seed_mode | lt::torrent_flags::upload_mode);
            if (paused) params.flags |= lt::torrent_flags::paused;
            else params.flags &= ~lt::torrent_flags::paused;
            params.file_priorities.assign(expected_files, lt::dont_download);
            for (size_t i = 0; i < selected; i++) {
                if (selection[i] < 0 || static_cast<size_t>(selection[i]) >= expected_files) return failure("Sélection de fichiers non valide.");
                params.file_priorities[selection[i]] = lt::default_priority;
            }
            auto handle = engine.session.add_torrent(std::move(params), error);
            if (error) return failure(error.message().c_str());
            engine.entries.emplace(id, Entry{name, folder, resume_file, handle});
            return nullptr;
        } catch (std::exception const& error) { return failure(error.what()); }
        catch (...) { return failure("Impossible de démarrer le torrent."); }
    }
}

char *yoru_torrent_status(void *opaque) {
    @autoreleasepool {
        auto& engine = *static_cast<Engine *>(opaque);
        try {
            engine.drain();
            if (std::chrono::steady_clock::now() - engine.last_save > std::chrono::seconds(25)) engine.save(false);
            NSMutableArray *rows = [NSMutableArray array];
            for (auto& [id, entry] : engine.entries) {
                auto status = entry.handle.status();
                auto left = status.is_finished ? 0 : std::max<int64_t>(0, status.total_wanted - status.total_wanted_done);
                auto const info = entry.handle.torrent_file();
                std::string content;
                if (info) {
                    auto const relative = info->num_files() == 1 ? info->files().file_path(lt::file_index_t{0}) : info->name();
                    content = (std::filesystem::path(entry.folder) / relative).string();
                }
                if (status.is_finished && !entry.complete) {
                    entry.handle.save_resume_data();
                    ++engine.pending;
                    entry.complete = true;
                }
                [rows addObject:@{
                    @"hash": text(id), @"name": text(entry.name), @"progress": @(status.is_finished ? 1.0 : status.progress),
                    @"state": @(state(status)), @"dlspeed": @(status.download_rate), @"amount_left": @(left),
                    @"num_seeds": @(status.num_seeds), @"content_path": text(content), @"save_path": text(entry.folder),
                    @"eta": @(status.download_rate > 0 ? left / status.download_rate : 0),
                    @"details": status.errc ? text(status.errc.message()) : [NSNull null]
                }];
            }
            return json(rows);
        } catch (...) { return nullptr; }
    }
}

char *yoru_torrent_files(void *opaque, const char *id) {
    @autoreleasepool {
        auto& engine = *static_cast<Engine *>(opaque);
        try {
            auto const it = engine.entries.find(id);
            if (it == engine.entries.end()) return nullptr;
            auto const& handle = it->second.handle;
            auto const info = handle.torrent_file();
            auto const& storage = info->files();
            auto const downloaded = handle.file_progress();
            auto const priorities = handle.get_file_priorities();
            NSMutableArray *rows = [NSMutableArray array];
            for (auto index : storage.file_range()) {
                auto total = storage.file_size(index);
                auto done = total > 0 ? std::min(1.0, static_cast<double>(downloaded[index]) / total) : 1.0;
                [rows addObject:@{@"name": text(storage.file_path(index)),
                                  @"priority": @(static_cast<int>(priorities[index])), @"progress": @(done)}];
            }
            return json(rows);
        } catch (...) { return nullptr; }
    }
}

char *yoru_torrent_action(void *opaque, const char *id, int start) {
    auto& engine = *static_cast<Engine *>(opaque);
    try {
        auto const it = engine.entries.find(id);
        if (it == engine.entries.end()) return failure("Transfert introuvable.");
        if (start) it->second.handle.resume(); else it->second.handle.pause();
        return nullptr;
    } catch (...) { return failure("Impossible de modifier le transfert."); }
}

void yoru_torrent_remove(void *opaque, const char *id) {
    auto& engine = *static_cast<Engine *>(opaque);
    auto const it = engine.entries.find(id);
    if (it == engine.entries.end()) return;
    engine.session.remove_torrent(it->second.handle);
    engine.entries.erase(it);
}

void yoru_torrent_save(void *opaque) {
    @autoreleasepool {
        try { static_cast<Engine *>(opaque)->save(true); } catch (...) {}
    }
}

char *yoru_torrent_peer(void *opaque, const char *id, const char *address, uint16_t port) {
    auto& engine = *static_cast<Engine *>(opaque);
    try {
        auto const it = engine.entries.find(id);
        if (it == engine.entries.end()) return failure("Transfert introuvable.");
        it->second.handle.connect_peer(lt::tcp::endpoint(lt::make_address(address), port));
        return nullptr;
    } catch (...) { return failure("Connexion au pair de test impossible."); }
}

uint16_t yoru_torrent_port(void *opaque) { return static_cast<Engine *>(opaque)->session.listen_port(); }
