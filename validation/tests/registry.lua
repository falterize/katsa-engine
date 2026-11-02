-- Explicit runner metadata keeps historical commands available without eager imports.
local Registry = {}
local entries = {
    ['--test-v108.1'] = { module = 'validation.tests.versions.v108_1.focused', mode = 'default' },
    ['--test-v108.4.shadow'] = { module = 'validation.tests.versions.v108_4.shadowProbe', mode = 'default' },
    ['--test-v108.4.render'] = { module = 'validation.tests.versions.v108_4.renderBugs', mode = 'default' },
    ['--test-v108.4.cars'] = {
        module = 'validation.tests.versions.v108_4.carsScene',
        mode = 'default',
    },
    ['--test-v108.4'] = { module = 'validation.tests.versions.v108_4.focused', mode = 'default' },
    ['--test-v108'] = { module = 'validation.tests.versions.v108.focused', mode = 'default' },
    ['--test-v107.2-authoring'] = {
        module = 'validation.tests.versions.v107_2.focused',
        mode = 'default',
    },
    ['--preview-v107.1'] = { module = 'validation.tests.versions.v107_1.preview', mode = 'default' },
    ['--test-v107.1-authoring'] = {
        module = 'validation.tests.versions.v107_1.focused',
        mode = 'default',
    },
    ['--test-v107.1'] = { module = 'validation.tests.versions.v107_1.runtime', mode = 'default' },
    ['--preview-v107'] = { module = 'validation.tests.versions.v107.preview', mode = 'default' },
    ['--test-v107'] = { module = 'validation.tests.versions.v107.runtime', mode = 'default' },
    ['--test-physics2d'] = { module = 'validation.tests.versions.v107.physics2D', mode = 'default' },
    ['--test-data-session'] = {
        module = 'validation.tests.versions.v106_8.dataSession',
        mode = 'default',
    },
    ['--test-foundation'] = {
        module = 'validation.tests.versions.v106_8.foundation',
        mode = 'default',
    },
    ['--benchmark-physics'] = {
        module = 'validation.tests.performance.physicsComparison',
        mode = 'default',
    },
    ['--test-soak'] = { module = 'validation.tests.performance.soak', mode = 'default' },
    ['--test-v106.8'] = { module = 'validation.tests.versions.v106_8.runtime', mode = 'default' },
    ['--test-menu-idle'] = {
        module = 'validation.tests.versions.v106_7.menuIdle',
        mode = 'default',
    },
    ['--test-skin-menu'] = {
        module = 'validation.tests.versions.v106_7.skinAndMenu',
        mode = 'default',
    },
    ['--test-v106.7'] = { module = 'validation.tests.versions.v106_7.runtime', mode = 'default' },
    ['--test-stare-shooter'] = {
        module = 'validation.tests.versions.v106_6.stareShooter',
        mode = 'default',
    },
    ['--test-v106.6'] = { module = 'validation.tests.versions.v106_6.runtime', mode = 'default' },
    ['--test-v106.5'] = { module = 'validation.tests.versions.v106_5.runtime', mode = 'default' },
    ['--profile-v106.5-loop'] = {
        module = 'validation.tests.versions.v106_4.frameLoop',
        mode = 'default',
    },
    ['--test-v106.4'] = { module = 'validation.tests.versions.v106_4.runtime', mode = 'default' },
    ['--profile-v106.4-loop'] = {
        module = 'validation.tests.versions.v106_4.frameLoop',
        mode = 'default',
    },
    ['--preview-v106.3'] = { module = 'validation.tests.versions.v106_3.preview', mode = 'default' },
    ['--test-v106.3'] = { module = 'validation.tests.versions.v106_3.runtime', mode = 'default' },
    ['--profile-v106.2-stutter'] = {
        module = 'validation.tests.versions.v106_2.stutter',
        mode = 'default',
    },
    ['--test-v106.2'] = { module = 'validation.tests.versions.v106_2.runtime', mode = 'default' },
    ['--test-v106.1'] = { module = 'validation.tests.versions.v106_1.runtime', mode = 'default' },
    ['--profile-v106.1-stutter'] = {
        module = 'validation.tests.versions.v106_1.stutter',
        mode = 'default',
    },
    ['--test-v106'] = { module = 'validation.tests.versions.v106.runtime', mode = 'default' },
    ['--test-v105.2'] = { module = 'validation.tests.versions.v105_2.runtime', mode = 'default' },
    ['--test-v105.1-quality'] = {
        module = 'validation.tests.versions.v105_1.quality',
        mode = 'default',
    },
    ['--test-v105.1-regression'] = {
        module = 'validation.tests.versions.v105_1.regression',
        mode = 'default',
    },
    ['--preview-v105'] = { module = 'validation.tests.versions.v105.preview', mode = 'default' },
    ['--test-v105-parallel'] = {
        module = 'validation.tests.versions.v105.parallelRegression',
        mode = 'default',
    },
    ['--benchmark-v105'] = { module = 'validation.tests.versions.v105.benchmark', mode = 'default' },
    ['--test-v105'] = { module = 'validation.tests.versions.v105.runtime', mode = 'default' },
    ['--test-structure'] = {
        module = 'validation.tests.integration.structureRuntime',
        mode = 'default',
    },
    ['--test-v104-selection'] = {
        module = 'validation.tests.versions.v104.selection',
        mode = 'default',
    },
    ['--test-v104'] = { module = 'validation.tests.versions.v104.runtime', mode = 'default' },
    ['--preview-v103'] = { module = 'validation.tests.versions.v103.preview', mode = 'default' },
    ['--stress-v103'] = { module = 'validation.tests.versions.v103.stress', mode = 'default' },
    ['--profile-v103-gc'] = {
        module = 'validation.tests.versions.v103.gcProfile',
        mode = 'default',
    },
    ['--profile-v103'] = { module = 'validation.tests.versions.v102.workProfile', mode = 'default' },
    ['--test-v103'] = { module = 'validation.tests.versions.v103.runtime', mode = 'default' },
    ['--probe-v103-jolt'] = { module = 'validation.tests.versions.v103.probe', mode = 'default' },
    ['--profile-v102-ab'] = {
        module = 'validation.tests.versions.v102.abProfile',
        mode = 'default',
    },
    ['--test-v102'] = { module = 'validation.tests.versions.v102.runtime', mode = 'default' },
    ['--preview-v102'] = { module = 'validation.tests.versions.v102.preview', mode = 'default' },
    ['--profile-v102'] = { module = 'validation.tests.versions.v102.workProfile', mode = 'default' },
    ['--compare-v101-static'] = {
        module = 'validation.tests.versions.v101.static',
        mode = 'default',
    },
    ['--profile-v101-work'] = {
        module = 'validation.tests.versions.v101.workProfile',
        mode = 'default',
    },
    ['--test-v101'] = { module = 'validation.tests.versions.v101.runtime', mode = 'default' },
    ['--compare-v101'] = { module = 'validation.tests.versions.v96.compare', mode = 'default' },
    ['--profile-v101'] = { module = 'validation.tests.versions.v97.profile', mode = 'default' },
    ['--test-v100'] = { module = 'validation.tests.versions.v100.runtime', mode = 'default' },
    ['--compare-v100'] = { module = 'validation.tests.versions.v96.compare', mode = 'default' },
    ['--profile-v100'] = { module = 'validation.tests.versions.v97.profile', mode = 'default' },
    ['--profile-v100-occlusion'] = {
        module = 'validation.tests.versions.v100.occlusionProfile',
        mode = 'default',
    },
    ['--probe-v99-dispatch'] = {
        module = 'validation.tests.versions.v99.dispatchProbe',
        mode = 'default',
    },
    ['--test-v99'] = { module = 'validation.tests.versions.v99.runtime', mode = 'default' },
    ['--compare-v99'] = { module = 'validation.tests.versions.v96.compare', mode = 'default' },
    ['--profile-v99'] = { module = 'validation.tests.versions.v97.profile', mode = 'default' },
    ['--profile-v98'] = { module = 'validation.tests.versions.v97.profile', mode = 'default' },
    ['--compare-v98'] = { module = 'validation.tests.versions.v96.compare', mode = 'default' },
    ['--test-v98'] = { module = 'validation.tests.versions.v98.runtime', mode = 'default' },
    ['--profile-v98-motion'] = { module = 'validation.tests.versions.v98.motion', mode = 'default' },
    ['--probe-v98-combined'] = {
        module = 'validation.tests.versions.v98.combinedProbe',
        mode = 'default',
    },
    ['--profile-v98-loading'] = {
        module = 'validation.tests.versions.v98.loading',
        mode = 'default',
    },
    ['--compare-v97'] = { module = 'validation.tests.versions.v96.compare', mode = 'default' },
    ['--probe-v97-shader'] = {
        module = 'validation.tests.versions.v97.shaderProbe',
        mode = 'default',
    },
    ['--test-v97'] = { module = 'validation.tests.versions.v97.runtime', mode = 'default' },
    ['--profile-v97'] = { module = 'validation.tests.versions.v97.profile', mode = 'default' },
    ['--compare-v96'] = { module = 'validation.tests.versions.v96.compare', mode = 'default' },
    ['--test-v96'] = { module = 'validation.tests.versions.v96.runtime', mode = 'default' },
    ['--profile-v96'] = { module = 'validation.tests.versions.v96.profile', mode = 'default' },
    ['--test-v89'] = { module = 'validation.tests.versions.v89.runtime', mode = 'default' },
    ['--profile-v89-interpreter'] = {
        module = 'validation.tests.versions.v86.profile',
        mode = 'default',
    },
    ['--test-v88'] = { module = 'validation.tests.versions.v88.runtime', mode = 'default' },
    ['--profile-v88-interpreter'] = {
        module = 'validation.tests.versions.v86.profile',
        mode = 'default',
    },
    ['--test-v87'] = { module = 'validation.tests.versions.v87.runtime', mode = 'default' },
    ['--profile-v87'] = { module = 'validation.tests.versions.v86.profile', mode = 'default' },
    ['--profile-v87-interpreter'] = {
        module = 'validation.tests.versions.v86.profile',
        mode = 'default',
    },
    ['--test-v86'] = { module = 'validation.tests.versions.v86.runtime', mode = 'default' },
    ['--profile-v86'] = { module = 'validation.tests.versions.v86.profile', mode = 'default' },
    ['--profile-v86-interpreter'] = {
        module = 'validation.tests.versions.v86.profile',
        mode = 'default',
    },
    ['--checks-v86'] = { module = 'validation.tests.versions.v86.checks', mode = 'default' },
    ['--test-v85'] = { module = 'validation.tests.versions.v85.runtime', mode = 'default' },
    ['--profile-v85'] = { module = 'validation.tests.versions.v85.profile', mode = 'default' },
    ['--test-v84'] = { module = 'validation.tests.versions.v84.runtime', mode = 'default' },
    ['--compare-v84'] = { module = 'validation.tests.versions.v84.compare', mode = 'default' },
    ['--test-v83'] = { module = 'validation.tests.versions.v83.runtime', mode = 'default' },
    ['--test-v82'] = { module = 'validation.tests.versions.v82.runtime', mode = 'default' },
    ['--profile-v81'] = { module = 'validation.tests.versions.v81.profile', mode = 'default' },
    ['--test-v81'] = { module = 'validation.tests.versions.v81.runtime', mode = 'default' },
    ['--test-v80'] = { module = 'validation.tests.versions.v80.runtime', mode = 'default' },
    ['--test-v79'] = { module = 'validation.tests.versions.v79.runtime', mode = 'default' },
    ['--profile-v79'] = { module = 'validation.tests.versions.v79.profile', mode = 'default' },
    ['--test-v78'] = { module = 'validation.tests.versions.v78.runtime', mode = 'default' },
    ['--profile-v78'] = { module = 'validation.tests.versions.v78.profile', mode = 'default' },
    ['--profile-v77'] = { module = 'validation.tests.versions.v77.profile', mode = 'default' },
    ['--test-v77'] = { module = 'validation.tests.versions.v77.runtime', mode = 'default' },
    ['--components-v77'] = { module = 'validation.tests.versions.v77.components', mode = 'default' },
    ['--test-v76'] = { module = 'validation.tests.versions.v76.runtime', mode = 'default' },
    ['--profile-systems-v76'] = {
        module = 'validation.tests.versions.v76.systems',
        mode = 'default',
    },
    ['--profile-v76'] = { module = 'validation.tests.versions.v76.profile', mode = 'default' },
    ['--test-v75'] = { module = 'validation.tests.versions.v75.runtime', mode = 'default' },
    ['--profile-v75'] = { module = 'validation.tests.versions.v75.profile', mode = 'default' },
    ['--test-v74'] = { module = 'validation.tests.versions.v74.runtime', mode = 'default' },
    ['--profile-v74'] = { module = 'validation.tests.versions.v74.profile', mode = 'default' },
    ['--profile-v73'] = { module = 'validation.tests.versions.v73.profile', mode = 'default' },
    ['--test-v73'] = { module = 'validation.tests.versions.v73.runtime', mode = 'default' },
    ['--test-v72'] = { module = 'validation.tests.versions.v72.runtime', mode = 'default' },
    ['--profile-v71'] = { module = 'validation.tests.versions.v71.profile', mode = 'default' },
    ['--test-v71'] = { module = 'validation.tests.versions.v71.runtime', mode = 'default' },
    ['--profile-v70'] = { module = 'validation.tests.versions.v70.profile', mode = 'default' },
    ['--test-v70'] = { module = 'validation.tests.versions.v70.runtime', mode = 'default' },
    ['--test-v69'] = { module = 'validation.tests.versions.v69.runtime', mode = 'default' },
    ['--test-v68'] = { module = 'validation.tests.versions.v68.runtime', mode = 'default' },
    ['--test-v67'] = { module = 'validation.tests.versions.v67.runtime', mode = 'default' },
    ['--test-v66'] = { module = 'validation.tests.versions.v66.runtime', mode = 'default' },
    ['--test-v65'] = { module = 'validation.tests.versions.v65.runtime', mode = 'default' },
    ['--test-v64'] = { module = 'validation.tests.versions.v64.runtime', mode = 'default' },
    ['--bake-xbot'] = { module = 'validation.tests.versions.v64-bake', mode = 'standalone' },
    ['--test-v63'] = { module = 'validation.tests.versions.v63.runtime', mode = 'default' },
    ['--test-v62'] = { module = 'validation.tests.versions.v62.runtime', mode = 'default' },
    ['--test-v61'] = { module = 'validation.tests.versions.v61.runtime', mode = 'default' },
    ['--test-v60'] = { module = 'validation.tests.versions.v60.runtime', mode = 'default' },
    ['--test-v59'] = { module = 'validation.tests.versions.v59.runtime', mode = 'default' },
    ['--test-v58'] = { module = 'validation.tests.versions.v58.runtime', mode = 'default' },
    ['--test-v57'] = { module = 'validation.tests.versions.v57.runtime', mode = 'default' },
    ['--test-v56'] = { module = 'validation.tests.versions.v56.runtime', mode = 'default' },
    ['--test-v55'] = { module = 'validation.tests.versions.v55.runtime', mode = 'default' },
    ['--compare-v55'] = { module = 'validation.tests.performance.compareV55', mode = 'default' },
    ['--test-node-catalog'] = { module = 'validation.tests.versions.v54.catalog', mode = 'default' },
    ['--test-v54'] = { module = 'validation.tests.versions.v54.runtime', mode = 'default' },
    ['--profile-v54'] = { module = 'validation.tests.versions.v54.profile', mode = 'default' },
    ['--preview-v53'] = { module = 'validation.tests.versions.v53.previews', mode = 'default' },
    ['--preview-v52'] = { module = 'validation.tests.versions.v52.previews', mode = 'default' },
    ['--test-v53'] = { module = 'validation.tests.versions.v53.runtime', mode = 'default' },
    ['--test-v52'] = { module = 'validation.tests.versions.v52.runtime', mode = 'default' },
    ['--test-v51'] = { module = 'validation.tests.versions.v51.runtime', mode = 'default' },
    ['--test-v50'] = { module = 'validation.tests.versions.v50.runtime', mode = 'default' },
    ['--preview-v50'] = { module = 'validation.tests.versions.v50.previews', mode = 'default' },
    ['--preview-v49'] = { module = 'validation.tests.versions.v49.previews', mode = 'default' },
    ['--test-v49'] = { module = 'validation.tests.versions.v49.runtime', mode = 'default' },
    ['--test-v48-inspector'] = {
        module = 'validation.tests.versions.v48.runtime',
        mode = 'extended',
    },
    ['--benchmark-shadows'] = {
        module = 'validation.tests.performance.shadowBenchmark',
        mode = 'default',
    },
    ['--test-v48'] = { module = 'validation.tests.versions.v48.runtime', mode = 'default' },
    ['--test-v47'] = { module = 'validation.tests.versions.v47.runtime', mode = 'default' },
    ['--benchmark'] = { module = 'validation.tests.performance.benchmark', mode = 'default' },
    ['--test-shadows'] = { module = 'validation.tests.integration.runtime', mode = 'extended' },
    ['--test'] = { module = 'validation.tests.versions.v107_1.runtime', mode = 'default' },
}

function Registry.contains(arguments)
    for _, argument in ipairs(arguments or {}) do
        if entries[argument] then
            return true
        end
    end
    return false
end

function Registry.create(arguments, manager)
    local runner
    for _, argument in ipairs(arguments or {}) do
        local entry = entries[argument]
        if entry then
            local constructor = require(entry.module).new
            if entry.mode == 'standalone' then
                runner = constructor()
            elseif entry.mode == 'extended' then
                runner = constructor(manager, true)
            else
                runner = constructor(manager)
            end
        end
    end
    return runner
end

return Registry
