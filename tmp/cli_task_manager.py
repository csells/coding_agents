
import json
import argparse
import os

TASKS_FILE = 'tasks.json'

def load_tasks():
    if os.path.exists(TASKS_FILE):
        with open(TASKS_FILE, 'r') as f:
            data = json.load(f)
            return data.get('tasks', []), data.get('next_id', 1)
    return [], 1

def save_tasks(tasks, next_id):
    with open(TASKS_FILE, 'w') as f:
        json.dump({'tasks': tasks, 'next_id': next_id}, f, indent=4)

def main():
    parser = argparse.ArgumentParser(description="CLI Task Manager")
    parser.add_argument('command', help="Command to execute (add, list, view, edit)")
    parser.add_argument('--description', '-d', help="Description of the task (for add command)")
    parser.add_argument('--estimate', '-e', type=int, help="Estimate for the task in hours (for add command)")
    parser.add_argument('--id', '-i', type=int, help="ID of the task (for view and edit commands)")

    args = parser.parse_args()

    tasks, next_id = load_tasks()

    if args.command == 'add':
        if not args.description:
            print("Error: Task description is required for 'add' command.")
            return

        estimate = 0
        if args.estimate is not None:
            if args.estimate < 0:
                print("Error: Estimate cannot be negative.")
                return
            estimate = args.estimate

        task = {
            'id': next_id,
            'description': args.description,
            'estimate': estimate
        }
        tasks.append(task)
        next_id += 1
        save_tasks(tasks, next_id)
        print(f"Task '{task['description']}' added with ID {task['id']} and estimate {task['estimate']} hours.")
        save_tasks(tasks, next_id)
    elif args.command == 'list':
        if not tasks:
            print("No tasks found.")
            return
        print("Tasks:")
        for task in tasks:
            print(f"  ID: {task['id']}, Description: {task['description']}, Estimate: {task['estimate']} hours")
    elif args.command == 'view':
        if not args.id:
            print("Error: Task ID is required for 'view' command.")
            return
        
        found_task = None
        for task in tasks:
            if task['id'] == args.id:
                found_task = task
                break
        
        if found_task:
            print(f"Task ID: {found_task['id']}")
            print(f"Description: {found_task['description']}")
            print(f"Estimate: {found_task['estimate']} hours")
        else:
            print(f"Error: Task with ID {args.id} not found.")
    elif args.command == 'edit':
        if not args.id:
            print("Error: Task ID is required for 'edit' command.")
            return

        found_task = None
        for task in tasks:
            if task['id'] == args.id:
                found_task = task
                break
        
        if found_task:
            if args.description:
                found_task['description'] = args.description
            
            if args.estimate is not None:
                if args.estimate < 0:
                    print("Error: Estimate cannot be negative.")
                    return
                found_task['estimate'] = args.estimate
            
            save_tasks(tasks, next_id)
            print(f"Task {found_task['id']} updated.")
        else:
            print(f"Error: Task with ID {args.id} not found.")
    else:
        print(f"Unknown command: {args.command}")

if __name__ == "__main__":
    main()
