resource "aws_ecr_repository" "app" {
  name = var.project

  # Immutable tags are the registry-side half of "deploy by digest".
  # A tag can never be repointed at different bytes after the fact.
  image_tag_mutability = "IMMUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }
}

resource "aws_ecr_lifecycle_policy" "app" {
  repository = aws_ecr_repository.app.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep the last 15 images; older revisions are not rollback targets"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 15
      }
      action = { type = "expire" }
    }]
  })
}
