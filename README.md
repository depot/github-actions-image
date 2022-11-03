# github-actions-image

Source for building Depot's GitHub Actions runner AMI.

## Workflow

1. Run `make apply-patch` to apply patches to GitHub's upstream
2. Edit any file in `generated` as desired
3. Run `make generate-patch` to persist changes to `generated` to patch file

## License

MIT License, see `LICENSE`.

Code based on GitHub's runner image is MIT licensed, copyright GitHub.
