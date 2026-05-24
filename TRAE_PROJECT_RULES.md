# Trae Agent Project Structure Rules

## Core Principles

1. **English Directory Names**: All project directories must be in English
2. **Organized Structure**: Files must be placed in appropriate subdirectories, not in root
3. **Index File**: Maintain a quick index file at the project root
4. **Structural Review**: Review existing structure before creating new files
5. **Conservative Modifications**: Keep structural changes minimal and infrequent

---

## Directory Structure Guidelines

### Multi-Project Root Layout (When in a parent directory with multiple projects)
```
{working-directory}/
├── TRAE_PROJECT_RULES.md          (This file - global rules)
├── PROJECT_INDEX.md               (Quick index of all Trae agent projects)
├── project1/                      (Individual project directory)
│   ├── src/                       (Source code)
│   ├── docs/                      (Documentation)
│   ├── config/                    (Configuration files)
│   ├── tests/                     (Test files)
│   ├── scripts/                   (Helper scripts)
│   ├── assets/                    (Images, resources)
│   └── PROJECT_INDEX.md           (Project-specific index)
├── project2/
│   └── (same structure as above)
└── ...
```

### Single Project Layout (When directly in a project directory)
```
{project-directory}/
├── TRAE_PROJECT_RULES.md          (This file - global rules)
├── PROJECT_INDEX.md               (Project index)
├── src/                           (Source code)
├── docs/                          (Documentation)
├── config/                        (Configuration files)
├── tests/                         (Test files)
├── scripts/                       (Helper scripts)
└── assets/                        (Images, resources)
```

### Recommended Subdirectories
- `src/` - Source code files
- `docs/` - Documentation, README, guides
- `config/` - Configuration files (.env, .json, .yaml)
- `tests/` - Test files and test data
- `scripts/` - Helper scripts, automation
- `assets/` - Images, data files, resources
- `dist/` - Build outputs (generated)
- `logs/` - Log files (generated)

---

## Agent Workflow

### Step 1: Start of Session
1. **Check Current Working Directory**: Identify the current root directory
2. **Look for Rules File**: Check if `TRAE_PROJECT_RULES.md` exists in the current directory
3. **Read Global Rules**: If found, read this file
4. **Read Project Index**: If `PROJECT_INDEX.md` exists, read it to understand existing projects
5. **Identify Context**: Determine if we're in a multi-project parent directory or a single project directory

### Step 2: Working on a Project
1. **Confirm Current Directory**: Ensure we're in the correct project folder
2. **Look for Project Index**: Check for `PROJECT_INDEX.md` in the current directory
3. **Review Current Structure**: List directory contents to understand layout
4. **Assess Structure**: Think about whether current structure is reasonable
5. **Modify Conservatively**: Only adjust structure if clearly necessary, keep changes minimal

### Step 3: Creating New Files
1. **Determine Category**: Decide which directory the file belongs in
2. **Use Existing Structure**: Place files in appropriate existing directories
3. **Create Directories Only When Needed**: Only create new directories if no suitable one exists
4. **Update Index**: After creating files, update the project's index file if it exists

---

## Project Index File Format

### Root Level: `PROJECT_INDEX.md`
```markdown
# Trae Agent Projects Index

## Active Projects

| Project Name | Directory | Purpose | Last Updated |
|--------------|-----------|---------|--------------|
| MailSystem | `MailSystem/` | Email-driven AI automation system | 2026-05-24 |
| MyModel | `MyModle/` | Custom AI models | 2026-05-20 |

## Archived Projects
- (old projects moved here)
```

### Project Level: `{project}/PROJECT_INDEX.md`
```markdown
# {Project Name} - Project Index

## Overview
Brief description of the project.

## Directory Structure
- `src/` - Source code
- `docs/` - Documentation
- `config/` - Configuration
- `tests/` - Tests

## Key Files
- [main.py](src/main.py) - Entry point
- [README.md](docs/README.md) - Documentation
- [config.json](config/config.json) - Configuration

## Recent Changes
- 2026-05-24: Added X feature
```

---

## Rules for File Creation

1. **Never Drop Files in Root**: Always place new files in appropriate subdirectories
2. **English Naming**: Use English for all directory and file names
3. **Meaningful Names**: Use descriptive, clear names
4. **Group Related Files**: Keep related files together in the same directory
5. **Avoid Over-Categorization**: Don't create too many nested directories

---

## Structural Modification Guidelines

### When to Modify Structure
- Current structure is clearly causing confusion
- New feature requires a new category of files
- Project has grown significantly beyond initial scope

### When NOT to Modify Structure
- Minor inconvenience
- Personal preference
- Structure works but isn't "perfect"
- First time working on the project

### Modification Process
1. Think carefully about the change
2. Consider if it's truly necessary
3. Make minimal, focused changes
4. Update index files accordingly
5. Document the change in the project index

---

## Example: Starting a New Project

### Scenario 1: In a multi-project parent directory
```
1. Check current directory - it's a parent folder with multiple projects
2. Read TRAE_PROJECT_RULES.md
3. Read PROJECT_INDEX.md
4. Create new project directory: `new-project/`
5. Create standard subdirectories: src/, docs/, config/, tests/
6. Create project's PROJECT_INDEX.md
7. Add project to root PROJECT_INDEX.md
8. Begin working within the structured directories
```

### Scenario 2: Directly in a new project directory
```
1. Check current directory - it's the new project folder
2. If TRAE_PROJECT_RULES.md doesn't exist, create it (copy from template or create new)
3. Create standard subdirectories: src/, docs/, config/, tests/
4. Create PROJECT_INDEX.md for the project
5. Begin working within the structured directories
```

---

## Note
These rules are guidelines to improve efficiency. Use judgment - if a different approach makes sense for a specific project, adapt while keeping the core principles in mind.

The key is:
- Keep files organized in subdirectories (not in root)
- Use English directory names
- Maintain an index file
- Review structure before making changes
- Keep structural modifications conservative
