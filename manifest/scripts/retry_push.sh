#!/bin/bash
retry_push() {
            set -x  # Enable debugging (prints commands as they are executed)
            local attempt=1
            local changes_stashed=false

            while [ $attempt -le $MAX_RETRIES ]; do
                # Check for local changes and stash only if there are any
                if ! git diff-index --quiet HEAD --; then
                    echo "Local changes detected, stashing..."
                    git stash
                    changes_stashed=true
                else
                    echo "No local changes to stash."
                    changes_stashed=false
                fi

                # Pull the latest changes with rebase
                echo "Pulling latest changes with rebase..."
                if git pull --rebase origin main; then
                    echo "Rebase succeeded."
                else
                    echo "Rebase conflict detected, attempting to resolve..."
                    rebase_attempt=1

                    while [ $rebase_attempt -le $REBASE_RETRIES ]; do
                        # Use 'theirs' strategy to resolve conflicts in specific file
                        git checkout --theirs manifest/values.yaml
                        git add manifest/values.yaml

                        # Try to continue the rebase after resolving the conflict
                        if git rebase --continue; then
                            echo "Rebase continued successfully after resolving conflict."
                            break  # Break out of the retry loop if rebase succeeds
                        else
                            echo "Rebase conflict resolution attempt $rebase_attempt failed."
                            ((rebase_attempt++))
                            sleep $REBASE_RETRY_DELAY
                        fi
                    done

                    # If all rebase retries failed, abort the rebase and exit the main loop
                    if [ $rebase_attempt -gt $REBASE_RETRIES ]; then
                        echo "Failed to resolve conflict after $REBASE_RETRIES attempts, aborting rebase."
                        git rebase --abort
                        return 1  # Exit the script with a failure code
                    fi
                fi

                # Apply the stashed changes if any
                if [ "$changes_stashed" = true ]; then
                    echo "Applying stashed changes..."
                    if git stash pop; then
                        echo "Stash pop succeeded."
                    else
                        echo "Stash pop failed, attempting to resolve conflicts..."
                        rebase_attempt=1  # Reset rebase attempt counter for stash pop conflicts

                        while [ $rebase_attempt -le $REBASE_RETRIES ]; do
                            # Use 'theirs' strategy to resolve conflict if detected
                            git checkout --theirs manifest/values.yaml
                            git add manifest/values.yaml

                            # Try to continue the rebase after resolving the conflict
                            if git rebase --continue; then
                                echo "Rebase continued successfully after resolving stash conflict."
                                break  # Break out of the retry loop if rebase succeeds
                            else
                                echo "Rebase conflict resolution attempt $rebase_attempt failed."
                                ((rebase_attempt++))
                                sleep $REBASE_RETRY_DELAY
                            fi
                        done

                        # If all rebase retries failed, abort the rebase and exit the main loop
                        if [ $rebase_attempt -gt $REBASE_RETRIES ]; then
                            echo "Failed to resolve stash conflict after $REBASE_RETRIES attempts, aborting rebase."
                            git rebase --abort
                            return 1  # Exit the script with a failure code
                        fi
                    fi
                else
                    echo "No stash applied, skipping stash pop."
                fi

                # Try to push the changes
                echo "Attempting to push the changes..."
                if git push origin main; then
                    echo "Push succeeded on attempt $attempt."
                    return 0  # Exit the script with a success code
                else
                    echo "Push failed on attempt $attempt. Retrying in $RETRY_DELAY seconds..."
                    ((attempt++))
                    sleep $RETRY_DELAY
                fi
            done

            echo "Push failed after $MAX_RETRIES attempts."
            return 1  # Exit the script with a failure code
           }
          MAX_RETRIES=10           # Number of retry attempts for push
          RETRY_DELAY=20           # Delay between push retries (in seconds)
          REBASE_RETRIES=10         # Number of retry attempts for conflict resolution during rebase
          REBASE_RETRY_DELAY=10    # Delay between rebase retries (in seconds)
          retry_push
