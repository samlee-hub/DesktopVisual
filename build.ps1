param(
    [switch]$Help,
    [string]$Root = '',
    [string]$TestRepoRoot = ''
)

$ErrorActionPreference = 'Stop'

if ($Help) {
    Write-Host 'Usage: .\build.ps1 [-Root <path>] [-TestRepoRoot <path>]'
    Write-Host 'Builds winagent.exe and <testrepo>\testwindow\bin\TestWindow.exe.'
    exit 0
}

$Resolver = Join-Path $PSScriptRoot 'scripts\Resolve-DesktopVisualRoot.ps1'
$Root = & $Resolver -Root $Root -StartPath $PSScriptRoot
$env:DESKTOPVISUAL_ROOT = $Root
$WinAgentSrc = Join-Path $Root 'src\winagent'
$WinAgentBin = Join-Path $Root 'bin'
$WinAgentExe = Join-Path $WinAgentBin 'winagent.exe'
if ([string]::IsNullOrWhiteSpace($TestRepoRoot)) {
    $siblingTestRepo = Join-Path (Split-Path -Parent $Root) 'testrepo'
    if (Test-Path -LiteralPath $siblingTestRepo) {
        $TestRepoRoot = $siblingTestRepo
    } else {
        $TestRepoRoot = 'D:\testrepo'
    }
}
$TestWindowBuild = Join-Path $TestRepoRoot 'testwindow\build.ps1'
if (-not (Test-Path -LiteralPath $TestWindowBuild)) {
    throw "TestWindow build script was not found: $TestWindowBuild"
}
$TestWindowRoot = Join-Path $TestRepoRoot 'testwindow'
$TestWindowSrc = Join-Path $TestWindowRoot 'src\main.cpp'
$TestWindowBin = Join-Path $TestWindowRoot 'bin'
$TestWindowExe = Join-Path $TestWindowBin 'TestWindow.exe'
if (-not (Test-Path -LiteralPath $TestWindowSrc)) {
    throw "TestWindow source was not found: $TestWindowSrc"
}

function Ensure-ProgramFilesX86Env {
    $value = [Environment]::GetEnvironmentVariable('ProgramFiles(x86)', 'Process')
    if ([string]::IsNullOrWhiteSpace($value)) {
        $value = [Environment]::GetEnvironmentVariable('ProgramFiles(x86)', 'Machine')
    }
    if ([string]::IsNullOrWhiteSpace($value)) {
        $drive = if ($env:SystemDrive) { $env:SystemDrive } else { 'C:' }
        $candidate = Join-Path $drive 'Program Files (x86)'
        if (Test-Path $candidate) {
            $value = $candidate
        }
    }
    if (-not [string]::IsNullOrWhiteSpace($value)) {
        Set-Item -LiteralPath 'Env:ProgramFiles(x86)' -Value $value
    }
    return $value
}

function Find-VsDevCmd {
    if (Get-Command cl.exe -ErrorAction SilentlyContinue) {
        return $null
    }

    $programFilesX86 = Ensure-ProgramFilesX86Env
    if (-not [string]::IsNullOrWhiteSpace($programFilesX86)) {
        $vswhere = Join-Path $programFilesX86 'Microsoft Visual Studio\Installer\vswhere.exe'
        if (Test-Path $vswhere) {
            $install = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath | Select-Object -First 1
            if ($install) {
                $candidate = Join-Path $install 'Common7\Tools\VsDevCmd.bat'
                if (Test-Path $candidate) {
                    return $candidate
                }
            }
        }
    }

    $known = 'D:\VS\visual\Common7\Tools\VsDevCmd.bat'
    if (Test-Path $known) {
        return $known
    }

    throw 'cl.exe was not found, and VsDevCmd.bat could not be located. Install Visual Studio 2022 C++ tools or run this script from a Developer PowerShell.'
}

function Invoke-VcCommand([string]$Command) {
    $vsDevCmd = Find-VsDevCmd
    if ($vsDevCmd) {
        # Send only the VsDevCmd.bat initialization output to nul. When cl.exe is
        # not already on PATH, VsDevCmd.bat probes vswhere.exe and can emit a
        # benign 'vswhere.exe is not recognized' line to stderr. That message is
        # harmless standalone (the toolchain still initializes and the build
        # completes), but a strict parent (ErrorActionPreference='Stop', e.g.
        # rc_check) that captures this child with 2>&1 promotes any native stderr
        # line into a terminating NativeCommandError and fails the build before it
        # compiles. Silencing only the VsDevCmd.bat prefix keeps the actual
        # compile command's stdout/stderr intact, so real compiler errors are
        # still surfaced and $LASTEXITCODE still reflects the compile result.
        $cmdLine = '"{0}" -no_logo -arch=amd64 -host_arch=amd64 1>nul 2>nul && {1}' -f $vsDevCmd, $Command
        & cmd.exe /d /s /c $cmdLine
    } else {
        & cmd.exe /d /s /c "$Command"
    }

    if ($LASTEXITCODE -ne 0) {
        throw "Build command failed with exit code $LASTEXITCODE"
    }
}

function ConvertTo-ResponseFileArgument([string]$Argument) {
    if ($Argument -match '[\s"]') {
        return '"' + ($Argument -replace '"', '\"') + '"'
    }
    return $Argument
}

New-Item -ItemType Directory -Force -Path $WinAgentBin | Out-Null

$sources = @(
    'main.cpp',
    'AdaptiveHumanMode.cpp',
    'AgentBoundary.cpp',
    'AgentPlanner.cpp',
    'VLMObservationContract.cpp',
    'VLMProvider.cpp',
    'MockVLMProvider.cpp',
    'VLMObservationValidator.cpp',
    'VLMObservationBoundary.cpp',
    'RuntimeCandidateValidator.cpp',
    'LocatorCandidate.cpp',
    'VLMCandidateBridge.cpp',
    'BrowserSurfaceNormalizer.cpp',
    'BrowserWorkflow.cpp',
    'BrowserWorkflowAdapter.cpp',
    'WebFormFieldLocator.cpp',
    'BrowserWorkflowVerifier.cpp',
    'BrowserWorkflowExecutor.cpp',
    'CommunicationWorkflow.cpp',
    'CommunicationWorkflowAdapter.cpp',
    'CommunicationWorkflowVerifier.cpp',
    'CommunicationWorkflowExecutor.cpp',
    'ExplorerWorkflow.cpp',
    'ExplorerWorkflowAdapter.cpp',
    'EvidenceFingerprint.cpp',
    'RuntimeEvidenceConsolidator.cpp',
    'SessionLifecycleManager.cpp',
    'WorkflowSystemBoundary.cpp',
    'ExperienceMemoryRecord.cpp',
    'ExperienceMemoryStore.cpp',
    'ExperienceMemoryIndex.cpp',
    'FailureAttributionNormalizer.cpp',
    'FailureAttributionIntegrator.cpp',
    'MemorySafetyBoundary.cpp',
    'WorkflowTemplateRecord.cpp',
    'WorkflowTemplateRegistry.cpp',
    'WorkflowTemplateCandidateExtractor.cpp',
    'WorkflowTemplateValidator.cpp',
    'WorkflowTemplateInstantiator.cpp',
    'WorkflowTemplateSafetyBoundary.cpp',
    'BatchWorkflowPlan.cpp',
    'BatchWorkflowPlanner.cpp',
    'BatchWorkflowValidator.cpp',
    'BatchWorkflowCoordinator.cpp',
    'DeveloperRCGate.cpp',
    'VersionIntegrityChecker.cpp',
    'EvidenceChainVerifier.cpp',
    'CapabilityMatrixBuilder.cpp',
    'WorkflowBoundaryAuditor.cpp',
    'DeveloperFullAccessPolicyVerifier.cpp',
    'ReleaseHardeningDeferredLedger.cpp',
    'HandoffPackageBuilder.cpp',
    'ValidationConsistencyChecker.cpp',
    'RegressionSkipPolicy.cpp',
    'ExplorerWorkflowVerifier.cpp',
    'ExplorerContextMenuHandler.cpp',
    'ExplorerWorkflowExecutor.cpp',
    'PlanCompiler.cpp',
    'CompiledPlanExecutor.cpp',
    'StepContractRuntimeAdapter.cpp',
    'StepExecutionVerifier.cpp',
    'ExecutionEvidencePack.cpp',
    'WinAgent.cpp',
    'RuntimeSession.cpp',
    'SessionManager.cpp',
    'SessionObserveCache.cpp',
    'SessionLocatorCache.cpp',
    'SessionCommandDispatcher.cpp',
    'LatencyTracker.cpp',
    'LatencyProfile.cpp',
    'ForegroundPreparation.cpp',
    'ForegroundPreempt.cpp',
    'UserAbortController.cpp',
    'WindowFinder.cpp',
    'WindowSession.cpp',
    'Screenshot.cpp',
    'GlobalDpiAwareFrame.cpp',
    'FrameRegistry.cpp',
    'TargetWindowLock.cpp',
    'ScreenshotCoordinateMapper.cpp',
    'VisibleOperationPolicy.cpp',
    'IndentationController.cpp',
    'LanguageScopeModel.cpp',
    'EditorAutoIndentModel.cpp',
    'CodeWritePlan.cpp',
    'PreInputCodeStructureVerifier.cpp',
    'RepairEditPolicy.cpp',
    'CursorAndBufferStateGuard.cpp',
    'IncrementalCodeInputVerifier.cpp',
    'RealKeyboardCodeInputPolicy.cpp',
    'TextInputVerifier.cpp',
    'CodeEditorTypingPolicy.cpp',
    'StructuredTextInputPolicy.cpp',
    'VisibleTextInputPolicy.cpp',
    'RealVlmRuntimeBridge.cpp',
    'VLMRuntimeBridge.cpp',
    'DeterministicActionBatch.cpp',
    'VisibleUIVerificationPolicy.cpp',
    'PyCharmVisibleWorkflow.cpp',
    'InputController.cpp',
    'Trace.cpp',
    'UiaController.cpp',
    'OcrController.cpp',
    'ImageMatcher.cpp',
    'Perception.cpp',
    'SimpleJson.cpp',
    'AppProfile.cpp',
    'MotionProfile.cpp',
    'MotionPacer.cpp',
    'MotionRecorder.cpp',
    'MotionSynthesizer.cpp',
    'ProjectRoot.cpp',
    'PermissionManager.cpp',
    'FileWorkflow.cpp',
    'FormSemantics.cpp',
    'DecisionEngine.cpp',
    'FailureAttribution.cpp',
    'CodingWorkflow.cpp',
    'RecoveryStrategy.cpp',
    'ObserveController.cpp',
    'Selector.cpp',
    'OperationTimelineProfiler.cpp',
    'OrchestrationLatencyController.cpp',
    'SafetyPolicy.cpp',
    'SafetyManifest.cpp',
    'CaseRunner.cpp',
    'StepContract.cpp',
    'StepContractValidator.cpp',
    'StepCompletionGate.cpp',
    'TaskConfirmation.cpp',
    'TaskCheckpoint.cpp',
    'TaskRecovery.cpp',
    'TaskSession.cpp',
    'TaskTemplateV2.cpp',
    'TaskRunner.cpp',
    'ReportWriter.cpp',
    'RuntimeContextGuard.cpp',
    'SafeContextRecovery.cpp',
    'TargetSemanticsGuard.cpp',
    'ExecutionOutcomeClassifier.cpp'
) | ForEach-Object { Join-Path $WinAgentSrc $_ }

$buildWorkDir = Join-Path $Root 'artifacts\build'
New-Item -ItemType Directory -Force -Path $buildWorkDir | Out-Null
$generatedTestWindowSrc = Join-Path $buildWorkDir 'testwindow_main.generated.cpp'
$testWindowRootForCpp = $TestWindowRoot.Replace('\', '\\')
([IO.File]::ReadAllText($TestWindowSrc, [Text.Encoding]::UTF8)).
    Replace('D:\\testrepo\\testwindow', $testWindowRootForCpp) |
    Set-Content -LiteralPath $generatedTestWindowSrc -Encoding UTF8

$winAgentResponseFile = Join-Path $buildWorkDir 'winagent_cl.rsp'
$compileWinAgentArgs = @(
    '/nologo',
    '/utf-8',
    '/std:c++17',
    '/EHsc',
    '/DUNICODE',
    '/D_UNICODE',
    '/D_SILENCE_EXPERIMENTAL_COROUTINE_DEPRECATION_WARNINGS',
    "/Fe:$WinAgentExe",
    "/Fo:$WinAgentBin\"
) + $sources + @(
    'user32.lib',
    'gdi32.lib',
    'gdiplus.lib',
    'windowscodecs.lib',
    'ole32.lib',
    'oleaut32.lib',
    'UIAutomationCore.lib',
    'windowsapp.lib',
    'ws2_32.lib'
)
Set-Content -LiteralPath $winAgentResponseFile -Value ($compileWinAgentArgs | ForEach-Object { ConvertTo-ResponseFileArgument $_ }) -Encoding ASCII
$compileWinAgent = 'cl.exe "{0}"' -f ('@' + $winAgentResponseFile)
Invoke-VcCommand $compileWinAgent
Write-Output "Built $WinAgentExe"

New-Item -ItemType Directory -Force -Path $TestWindowBin | Out-Null
$testWindowResponseFile = Join-Path $buildWorkDir 'testwindow_cl.rsp'
$compileTestWindowArgs = @(
    '/nologo',
    '/std:c++17',
    '/EHsc',
    '/DUNICODE',
    '/D_UNICODE',
    "/Fe:$TestWindowExe",
    "/Fo:$TestWindowBin\",
    $generatedTestWindowSrc,
    'user32.lib',
    'gdi32.lib'
)
Set-Content -LiteralPath $testWindowResponseFile -Value ($compileTestWindowArgs | ForEach-Object { ConvertTo-ResponseFileArgument $_ }) -Encoding ASCII
$compileTestWindow = 'cl.exe "{0}"' -f ('@' + $testWindowResponseFile)
Invoke-VcCommand $compileTestWindow
Write-Output "Built $TestWindowExe"
Write-Output 'Build succeeded'
