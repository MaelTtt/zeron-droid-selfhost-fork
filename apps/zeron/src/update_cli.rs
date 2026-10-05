//! `zeron update` — check for and apply a newer release, natively (the same
//! flow `edge/src/install.sh` performs: download → verify → symlink swap →
//! service restart). macOS app bundles swap the bundle instead; source builds
//! are report-only.

use anyhow::bail;
use zeron_update::{InstallKind, current_version, is_fork_version, version_newer};

/// `--check` prints the verdict and exits (nonzero when an update is available,
/// so scripts can gate on it). Fork installs resolve the newest `-mael.N`
/// release (edge feed or GitHub) instead of the stock feed.
pub async fn update(edge_url: &str, check_only: bool) -> anyhow::Result<()> {
    let fork = std::env::var("ZERON_FORK").is_ok_and(|v| !v.trim().is_empty());
    // Fork installs resolve `-mael.N` releases (GitHub or edge feed);
    // stock keeps the edge feed. The download base rides along so a GitHub
    // release stages from its own assets.
    let (manifest, download_base) = if fork {
        match zeron_update::fetch_fork_update(edge_url).await? {
            Some(resolved) => (resolved.manifest, Some(resolved.download_base)),
            None => {
                println!("zeron {} is up to date.", current_version());
                return Ok(());
            }
        }
    } else {
        (zeron_update::fetch_latest(edge_url).await?, None)
    };
    let current = current_version();
    if !version_newer(&manifest.version, current) {
        println!(
            "zeron {current} is up to date (latest: {}).",
            manifest.version
        );
        return Ok(());
    }
    println!("zeron {current} → {} available", manifest.version);
    if check_only {
        if fork && !is_fork_version(&manifest.version) {
            println!(
                "note: forked build ({current}) — official {} won't overwrite it. To take the release with fork patches, run `zeron-fork-update`.",
                manifest.version
            );
        }
        std::process::exit(1);
    }
    // A fork install may one-click apply fork releases (same `-mael.N`
    // lineage — staging is fork-aware); a stock release would overwrite the
    // fork, so that still refuses.
    if fork && !is_fork_version(&manifest.version) {
        bail!(
            "this is the mael fork ({current}); `zeron update` would overwrite it with stock {}.\nTo take the official release while keeping the fork patches, run `zeron-fork-update` instead — it rebases onto {} and rebuilds.",
            manifest.version,
            manifest.version
        );
    }

    let install = zeron_update::detect_install();
    if let Some(blocker) = install.desktop_update_blocker() {
        bail!("{blocker}");
    }
    match install {
        InstallKind::Managed { app_root } => {
            println!(
                "downloading {}…",
                zeron_update::headless_artifact(&manifest.version)
            );
            match download_base {
                Some(base) => {
                    zeron_update::stage_headless_from_base(&base, &manifest, &app_root).await?
                }
                None => zeron_update::stage_headless(edge_url, &manifest, &app_root).await?,
            };
            zeron_update::apply_headless(&app_root, &manifest.version)?;
            println!(
                "installed {} (current → {})",
                app_root
                    .join(zeron_update::versioned_dir_name(&manifest.version))
                    .display(),
                manifest.version
            );
            match zeron_update::restart_service() {
                Ok(()) => println!("engine service restarted."),
                Err(err) => println!(
                    "note: service restart failed ({err:#}) — restart the engine manually to finish."
                ),
            }
            Ok(())
        }
        InstallKind::MacApp { bundle } => {
            println!(
                "downloading {}…",
                zeron_update::mac_app_artifact(&manifest.version)
            );
            let data_dir = super::paths::data_dir();
            let staged = zeron_update::stage_mac_app(edge_url, &manifest, &data_dir).await?;
            zeron_update::apply_mac_app(&staged, &bundle)?;
            println!("updated {} — relaunch Zeron to finish.", bundle.display());
            Ok(())
        }
        #[cfg(windows)]
        InstallKind::WindowsPortable { directory } => {
            let staged = zeron_update::windows::stage(edge_url, &manifest, &directory).await?;
            zeron_update::windows::apply(&staged, &directory, false)?;
            println!(
                "updated to {} — relaunch Zeron to finish.",
                manifest.version
            );
            Ok(())
        }
        InstallKind::Unmanaged => {
            if fork {
                bail!(
                    "this fork build is not update-managed (source build or hand-copied).\n\
                     Download the new release tarball from {} and run its install.sh, or rebuild from source.",
                    zeron_update::fork_releases_page()
                )
            }
            bail!(
                "this binary is not update-managed (source build or hand-copied).\n\
                 Linux: curl -fsSL https://zeron.sh/install.sh | sh, or run install.sh from the release tarball\n\
                 macOS: download the new Zeron.app dmg, or rebuild from source.\n\
                 Windows: install with the Zeron setup .exe from {}, or rebuild from source.",
                zeron_update::LATEST_RELEASE_PAGE
            )
        }
    }
}
