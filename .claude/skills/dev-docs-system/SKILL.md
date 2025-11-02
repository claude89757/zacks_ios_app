---
name: dev-docs-system
description: Maintains task context and focus during large development tasks by creating and managing structured documentation (plan, context, tasks) in docs/dev/active/. This skill should be used when exiting plan mode with accepted plans that involve 3+ implementation steps, when users ask to continue working on existing tasks, or when complex multi-file changes risk losing track of the original goal. Prevents scope creep and amnesia during long implementations.
---

# Dev Docs System

## Overview

The Dev Docs System prevents the common problem of losing focus during large implementation tasks. It creates and maintains three essential documentation files that keep implementation aligned with the original plan and capture evolving context.

**Purpose**: Combat "scope creep amnesia" where Claude starts implementing a planned feature but gradually loses track of the original goal due to tangents, debugging, or complexity.

**Core files created**:
- `[task]-plan.md` - The accepted plan (unchanging reference)
- `[task]-context.md` - Living document of decisions and key files
- `[task]-tasks.md` - Checklist with completion tracking

## When to Use This Skill

### Automatic Triggers (Create Dev Docs Without Asking)

Use this skill automatically in these scenarios:

1. **Exiting Plan Mode with Large Tasks**
   - Plan has 3 or more distinct implementation steps
   - Plan involves changes across multiple files (3+)
   - Plan includes complex features with multiple components
   - Example: "Add video sharing feature with export, UI updates, and networking"

2. **Continuing Existing Tasks**
   - User says "continue working on [task]"
   - User references a feature that was previously started
   - User asks "what were we working on?"
   - Action: Check `docs/dev/active/` for existing task directories, read all three files

### Ask User First (Medium-Sized Tasks)

For these scenarios, ask the user if they want dev docs created:

1. **Medium Tasks (2-3 steps)**
   - Simple feature additions
   - Single-file refactoring
   - Bug fixes with multiple related changes
   - Prompt: "This task has [N] steps. Create dev docs to track progress? (Recommended for tasks taking >15 minutes)"

2. **Unclear Scope**
   - Plan doesn't clearly indicate size
   - User hasn't provided enough detail
   - Prompt: "Should I create dev docs to track this work?"

### Never Use (Skip Dev Docs)

Skip this skill for trivial tasks:

1. Single-step changes (e.g., "add a comment", "rename variable")
2. Tasks that take <5 minutes
3. Simple grep/search operations
4. Reading or explaining code
5. User explicitly says "no need to track this"

## Workflow

### Starting a New Task

When plan mode exits with an accepted plan that qualifies for dev docs:

**Step 1: Run the initialization script**

```bash
python3 scripts/init_task_docs.py "Task Name" \
  --project-root /path/to/project \
  --plan "Brief overview from accepted plan" \
  --steps "Step 1\nStep 2\nStep 3" \
  --tasks "Task 1\nTask 2\nTask 3"
```

The script will:
- Create `docs/dev/active/[task-name]/` directory
- Generate three files from templates in `assets/templates/`
- Pre-populate with task information
- Output success message with next steps

**Step 2: Verify files created**

Confirm the three files exist:
- `docs/dev/active/[task-name]/[task-name]-plan.md`
- `docs/dev/active/[task-name]/[task-name]-context.md`
- `docs/dev/active/[task-name]/[task-name]-tasks.md`

**Step 3: Begin implementation**

Start working on the first task, following the plan. Reference these files as needed.

### During Implementation

**Update context.md immediately when:**
- Making architectural decisions (which approach to use, why)
- Discovering important implementation details or gotchas
- Adding or modifying key files (note the file path and purpose)
- Encountering blockers or questions
- Finding useful references or documentation

**Update tasks.md immediately when:**
- Completing a task (mark with `[x]`)
- Discovering new sub-tasks that need to be added
- Updating progress counter (e.g., "3/10 tasks completed")
- Always update "Last Updated" timestamp

**DO NOT update plan.md** - it remains unchanged as the original reference point.

**Critical practice**: Update files in real-time, not at the end. This ensures context is never lost if work is interrupted.

### Continuing an Existing Task

When user says "continue working on [task]" or references previous work:

**Step 1: Check for existing task docs**

```bash
ls docs/dev/active/
```

Look for directories matching the task name or related keywords.

**Step 2: Read all three files**

Read in this order:
1. `[task]-plan.md` - Understand the original goal
2. `[task]-tasks.md` - See what's completed and what's pending
3. `[task]-context.md` - Get up to speed on decisions and key files

**Step 3: Resume from last checkpoint**

Find the first incomplete task in tasks.md and continue from there, staying aligned with the original plan.

**Step 4: Update timestamps**

Update "Last Updated" in tasks.md and context.md to current time.

## File Descriptions

### [task]-plan.md (The Reference)

**Purpose**: Unchanging snapshot of the accepted plan

**Contains**:
- Task name and creation date
- Plan overview (what and why)
- Implementation steps (the approach)
- Success criteria (definition of done)

**Rules**:
- NEVER modify after creation
- Serves as the "north star" to prevent scope creep
- If plan changes significantly, create a new task directory

### [task]-context.md (The Living Document)

**Purpose**: Evolving context that helps resume work

**Contains**:
- Key files modified (file path + purpose)
- Architecture decisions (what, why, alternatives considered)
- Important context (gotchas, edge cases, dependencies)
- SwiftUI/SwiftData specific notes (model changes, MVVM patterns)
- Blockers and questions
- Resources and references used

**Rules**:
- Update immediately when making decisions
- Update immediately when modifying files
- Include reasoning ("why") not just facts ("what")
- Keep it concise but complete

**iOS Project-Specific Guidance**:
Since this is for an iOS project using SwiftUI + SwiftData + MVVM:
- Note SwiftData @Model changes and relationships
- Document ViewModel configuration requirements
- Track which files need Xcode target membership
- Note Info.plist permission updates
- Document test data or simulator setup needs

### [task]-tasks.md (The Checklist)

**Purpose**: Track granular progress and ensure nothing is forgotten

**Contains**:
- Task breakdown (from plan steps)
- Testing checklist
- Code quality checklist (iOS-specific)
- Completion criteria

**Rules**:
- Mark tasks complete `[x]` IMMEDIATELY after finishing
- Update progress counter when marking tasks
- Update "Last Updated" timestamp
- Add new tasks if discovered during work
- Never remove tasks, mark as completed or N/A

**iOS Project Checklist Items**:
The template includes iOS-specific checks:
- Files added to Xcode project target (white, not gray in navigator)
- Info.plist updated with required permissions
- No SwiftData schema conflicts
- Error handling follows project patterns (@Observable, LocalizedError)
- MVVM architecture maintained
- No security vulnerabilities

## iOS Project Integration

This skill is tailored for the Zacks Tennis iOS app project structure:

**Project Structure Awareness**:
- `zacks_tennis/Core/Models/` - SwiftData @Model classes
- `zacks_tennis/Core/Services/` - Singleton services (@MainActor, @Observable)
- `zacks_tennis/Features/[Feature]/Views/` - SwiftUI views
- `zacks_tennis/Features/[Feature]/ViewModels/` - MVVM ViewModels

**Common iOS Task Patterns**:

When adding a new feature:
1. Create SwiftData model in Core/Models/ (if needed)
2. Create or update service in Core/Services/ (if needed)
3. Create feature module in Features/[FeatureName]/
4. Create Views and ViewModels following MVVM
5. Update MainTabView.swift (if adding tab)
6. Update sharedModelContainer schema (if new model)
7. Update Info.plist (if new permissions)
8. Write tests

Track these in tasks.md and note key decisions in context.md.

## Examples

### Example 1: Starting a Large Task

**User**: *Accepts plan to "Add video sharing feature"*

**Claude Action**:
```bash
# Automatically create dev docs (4+ steps = large task)
python3 scripts/init_task_docs.py "Video Sharing Feature" \
  --project-root /Users/claude89757/ugit/zacks_ios_app \
  --plan "Add ability to share edited video clips via iOS Share Sheet" \
  --steps "1. Create ShareService\n2. Add Share UI to VideoDetailView\n3. Implement export with metadata\n4. Add analytics tracking\n5. Write tests" \
  --tasks "Create Core/Services/ShareService.swift\nUpdate VideoDetailView with share button\nImplement prepareForSharing in VideoProcessingService\nAdd share analytics to NetworkService\nWrite ShareService unit tests\nTest on real device"
```

Then immediately start on first task while updating context.md with decisions.

### Example 2: Medium Task (Ask First)

**User**: *Accepts plan to "Fix video export quality bug"*

**Claude Action**:
- Recognize 2-step plan (medium task)
- Ask: "This task involves modifying VideoProcessingService export settings and testing. Create dev docs to track progress? (Recommended for tasks taking >15 minutes)"
- If user says yes, create dev docs
- If user says no, proceed without dev docs

### Example 3: Continuing Existing Task

**User**: "Continue working on the video sharing feature"

**Claude Action**:
```bash
# Check for existing docs
ls docs/dev/active/
# Found: video-sharing-feature/

# Read all three files
cat docs/dev/active/video-sharing-feature/video-sharing-feature-plan.md
cat docs/dev/active/video-sharing-feature/video-sharing-feature-tasks.md
cat docs/dev/active/video-sharing-feature/video-sharing-feature-context.md

# Analyze:
# - Plan: Add Share Sheet functionality
# - Tasks: 3/6 completed (ShareService created, UI updated, metadata export pending)
# - Context: Decision to use AVAssetExportSession, files modified, blocker on analytics API key

# Resume from task 4: "Add share analytics to NetworkService"
# Update Last Updated timestamps in tasks.md and context.md
```

### Example 4: Preventing Scope Creep

**Scenario**: While implementing video sharing, discover the thumbnail generation is slow.

**Without Dev Docs**:
- Start optimizing thumbnails
- Spend 30 minutes on optimization
- Forget about original share feature
- Get distracted by other issues
- 2 hours later, video sharing still not done

**With Dev Docs**:
- Notice thumbnail issue
- Add to context.md: "Note: Thumbnail generation is slow, consider optimizing in future task"
- Stay focused on share feature tasks
- Complete original plan
- Create separate task for thumbnail optimization later

## Best Practices

1. **Create dev docs early** - Right after plan mode, not halfway through
2. **Update in real-time** - Don't batch updates at the end
3. **Mark tasks complete immediately** - Builds momentum and tracks progress
4. **Use context.md liberally** - Better to over-document than under-document
5. **Read all three files when resuming** - Don't skip, especially context.md
6. **Keep plan.md sacred** - Never modify the original plan
7. **Reference file paths** - Always include full paths (e.g., `zacks_tennis/Core/Services/ShareService.swift`)
8. **Note the "why"** - Decisions should include reasoning, not just facts
9. **Update timestamps** - Helps identify stale tasks
10. **Trust the system** - If unsure whether to create docs, create them (low cost, high value)

## Resources

### scripts/init_task_docs.py

Python script that creates the task directory structure and populates templates.

**Usage**:
```bash
python3 scripts/init_task_docs.py <task-name> [options]

Options:
  --project-root PATH   Path to project root (default: git root or cwd)
  --plan TEXT          Plan overview text
  --steps TEXT         Implementation steps (newline-separated)
  --criteria TEXT      Success criteria
  --tasks TEXT         Task list (newline-separated)
```

**Output**:
- Creates `docs/dev/active/[task-name]/` directory
- Generates three .md files from templates
- Populates with provided content or placeholders
- Reports success and next steps

### assets/templates/

Contains markdown templates for the three doc files:

- `plan-template.md` - Template for [task]-plan.md
- `context-template.md` - Template for [task]-context.md
- `tasks-template.md` - Template for [task]-tasks.md

Templates use `{PLACEHOLDER}` syntax for variable substitution by the init script.

## Troubleshooting

**Q: Dev docs directory not found when continuing task**
- Check `docs/dev/active/` exists in project
- Verify task name slug (lowercase, hyphens for spaces)
- List all active tasks: `ls docs/dev/active/`

**Q: Script fails with "Template not found"**
- Ensure skill is properly installed with assets/ directory
- Check templates exist in `assets/templates/`
- Verify script can find skill directory (uses `__file__` parent)

**Q: Should I create dev docs for this task?**
- 3+ steps? → Yes, automatic
- 2-3 steps, >15 min? → Ask user
- 1 step or <5 min? → No
- When in doubt → Create them (better safe than sorry)

**Q: Task scope changed significantly during implementation**
- Don't modify plan.md
- Note changes in context.md under "Architecture Decisions"
- If completely different, consider creating new task directory
- Mark original tasks as N/A if no longer applicable

**Q: Forgot to update dev docs during work**
- Update now before continuing
- Review what was done and update context.md
- Mark completed tasks in tasks.md
- Update timestamps
- Resume with docs current
