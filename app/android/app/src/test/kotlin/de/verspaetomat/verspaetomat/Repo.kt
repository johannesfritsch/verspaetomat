package de.verspaetomat.verspaetomat

import java.io.File

/**
 * Where the committed artefacts are, from a unit test.
 *
 * `verspaetomat.repo` is set by app/android/app/build.gradle.kts from
 * `rootProject.projectDir.parentFile.parentFile`. Nothing here skips when a file is missing: a
 * suite that skips is a suite that rots, which is what happened to the Swift assertion at
 * Geofence.swift:219-223.
 */
object Repo {
    val root: File by lazy {
        val p = System.getProperty("verspaetomat.repo")
            ?: error("verspaetomat.repo is not set; run the tests through Gradle")
        File(p).also { require(it.isDirectory) { "verspaetomat.repo=$p is not a directory" } }
    }

    /**
     * The extract that ships. `app/assets/stations/stations.vst` is the copy inside the build;
     * `site/static/stations/stations-<n>.vst` is the same bytes published on the website. Both are
     * committed, so this never returns null on a checked-out tree.
     */
    val extractFile: File by lazy {
        val asset = File(root, "app/assets/stations/stations.vst")
        if (asset.isFile) return@lazy asset
        val published = File(root, "site/static/stations/")
            .listFiles { f -> f.isFile && f.name.endsWith(".vst") }
            ?.sortedBy { it.name }
            ?.lastOrNull()
        published ?: error(
            "no station extract in the tree: neither app/assets/stations/stations.vst nor " +
                "site/static/stations/stations-<n>.vst. Run `stellwerk stations extract`.",
        )
    }

    /**
     * The probe fixture all four readers are compared against
     * (`stellwerk stations probes`, spec §5.2).
     *
     * `-Dverspaetomat.probes=<path>` overrides it, which is how a freshly generated fixture is
     * tried before it lands.
     */
    val probesFile: File by lazy {
        val override = System.getProperty("verspaetomat.probes")
        if (override != null) return@lazy File(override)
        File(root, "testdata/stations/nearby-probes.tsv")
    }
}
