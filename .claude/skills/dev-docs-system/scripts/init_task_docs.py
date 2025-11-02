#!/usr/bin/env python3
"""
Initialize task documentation structure for the Dev Docs System.

This script creates a task directory in docs/dev/active/ with three key files:
- [task]-plan.md: The accepted implementation plan
- [task]-context.md: Key files, decisions, and context
- [task]-tasks.md: Checklist of tasks to complete

Usage:
    python init_task_docs.py <task-name> [--project-root /path/to/project]
"""

import os
import sys
import argparse
from datetime import datetime
from pathlib import Path


def slugify(text):
    """Convert task name to URL-friendly slug."""
    return text.lower().replace(' ', '-').replace('_', '-')


def get_timestamp():
    """Get current timestamp in readable format."""
    return datetime.now().strftime('%Y-%m-%d %H:%M:%S')


def create_task_directory(task_name, project_root):
    """Create the task directory structure."""
    slug = slugify(task_name)
    task_dir = project_root / 'docs' / 'dev' / 'active' / slug

    # Create directory
    task_dir.mkdir(parents=True, exist_ok=True)

    return task_dir, slug


def load_template(template_name, skill_dir):
    """Load a template file from assets/templates/."""
    template_path = skill_dir / 'assets' / 'templates' / template_name

    if not template_path.exists():
        raise FileNotFoundError(f"Template not found: {template_path}")

    with open(template_path, 'r') as f:
        return f.read()


def fill_template(template_content, replacements):
    """Replace placeholders in template with actual values."""
    for key, value in replacements.items():
        placeholder = '{' + key + '}'
        template_content = template_content.replace(placeholder, value)

    return template_content


def create_plan_file(task_dir, task_name, slug, skill_dir, plan_content='', steps='', criteria=''):
    """Create the plan.md file from template."""
    template = load_template('plan-template.md', skill_dir)

    replacements = {
        'TASK_NAME': task_name,
        'TIMESTAMP': get_timestamp(),
        'PLAN_OVERVIEW': plan_content or '[Add plan overview here]',
        'PLAN_STEPS': steps or '[Add implementation steps here]',
        'SUCCESS_CRITERIA': criteria or '[Add success criteria here]'
    }

    content = fill_template(template, replacements)

    plan_file = task_dir / f'{slug}-plan.md'
    with open(plan_file, 'w') as f:
        f.write(content)

    return plan_file


def create_context_file(task_dir, task_name, slug, skill_dir):
    """Create the context.md file from template."""
    template = load_template('context-template.md', skill_dir)

    replacements = {
        'TASK_NAME': task_name,
        'TIMESTAMP': get_timestamp()
    }

    content = fill_template(template, replacements)

    context_file = task_dir / f'{slug}-context.md'
    with open(context_file, 'w') as f:
        f.write(content)

    return context_file


def create_tasks_file(task_dir, task_name, slug, skill_dir, tasks=''):
    """Create the tasks.md file from template."""
    template = load_template('tasks-template.md', skill_dir)

    # Convert tasks to checklist format if provided
    if tasks:
        task_list = '\n'.join([f'- [ ] {task.strip()}' for task in tasks.split('\n') if task.strip()])
        total_tasks = len([t for t in tasks.split('\n') if t.strip()])
    else:
        task_list = '- [ ] [Add tasks here]'
        total_tasks = 0

    replacements = {
        'TASK_NAME': task_name,
        'TIMESTAMP': get_timestamp(),
        'TOTAL_TASKS': str(total_tasks),
        'TASK_LIST': task_list
    }

    content = fill_template(template, replacements)

    tasks_file = task_dir / f'{slug}-tasks.md'
    with open(tasks_file, 'w') as f:
        f.write(content)

    return tasks_file


def main():
    parser = argparse.ArgumentParser(
        description='Initialize task documentation for Dev Docs System'
    )
    parser.add_argument('task_name', help='Name of the task (e.g., "Video Sharing Feature")')
    parser.add_argument('--project-root', type=str, help='Path to project root directory')
    parser.add_argument('--plan', type=str, help='Plan content')
    parser.add_argument('--steps', type=str, help='Implementation steps')
    parser.add_argument('--criteria', type=str, help='Success criteria')
    parser.add_argument('--tasks', type=str, help='Task list (newline-separated)')

    args = parser.parse_args()

    # Determine project root
    if args.project_root:
        project_root = Path(args.project_root)
    else:
        # Assume current directory or find git root
        project_root = Path.cwd()
        # Try to find git root
        current = Path.cwd()
        while current != current.parent:
            if (current / '.git').exists():
                project_root = current
                break
            current = current.parent

    # Determine skill directory (where this script is located)
    skill_dir = Path(__file__).parent.parent

    try:
        # Create task directory
        task_dir, slug = create_task_directory(args.task_name, project_root)
        print(f"✅ Created task directory: {task_dir}")

        # Create the three files
        plan_file = create_plan_file(
            task_dir, args.task_name, slug, skill_dir,
            args.plan or '', args.steps or '', args.criteria or ''
        )
        print(f"✅ Created: {plan_file.name}")

        context_file = create_context_file(task_dir, args.task_name, slug, skill_dir)
        print(f"✅ Created: {context_file.name}")

        tasks_file = create_tasks_file(
            task_dir, args.task_name, slug, skill_dir, args.tasks or ''
        )
        print(f"✅ Created: {tasks_file.name}")

        print(f"\n🎉 Task documentation initialized successfully!")
        print(f"\nNext steps:")
        print(f"1. Update {slug}-plan.md with the accepted plan")
        print(f"2. Track key decisions in {slug}-context.md")
        print(f"3. Mark tasks complete in {slug}-tasks.md as you work")

    except Exception as e:
        print(f"❌ Error: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == '__main__':
    main()
