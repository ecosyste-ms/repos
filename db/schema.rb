# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[7.0].define(version: 2023_05_30_102932) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "plpgsql"

  create_table "dependencies", force: :cascade do |t|
    t.integer "manifest_id"
    t.integer "repository_id"
    t.boolean "optional", default: false
    t.string "package_name"
    t.string "ecosystem"
    t.string "requirements"
    t.string "kind"
    t.boolean "direct", default: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["ecosystem", "package_name"], name: "index_dependencies_on_ecosystem_and_package_name"
    t.index ["manifest_id"], name: "index_dependencies_on_manifest_id"
  end

  create_table "exports", force: :cascade do |t|
    t.string "date"
    t.string "bucket_name"
    t.integer "repositories_count"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "hosts", force: :cascade do |t|
    t.string "name"
    t.string "url"
    t.string "kind"
    t.integer "repositories_count", default: 0
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "org"
    t.integer "owners_count", default: 0
  end

  create_table "manifests", force: :cascade do |t|
    t.integer "repository_id"
    t.string "ecosystem"
    t.string "filepath"
    t.string "sha"
    t.string "branch"
    t.string "kind"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "tag_id"
    t.index ["repository_id"], name: "index_manifests_on_repository_id"
    t.index ["tag_id"], name: "index_manifests_on_tag_id"
  end

  create_table "owners", force: :cascade do |t|
    t.integer "host_id"
    t.string "login"
    t.string "name"
    t.string "uuid"
    t.string "kind"
    t.string "description"
    t.string "email"
    t.string "website"
    t.string "location"
    t.string "twitter"
    t.string "company"
    t.string "avatar_url"
    t.integer "repositories_count", default: 0
    t.datetime "last_synced_at"
    t.json "metadata", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index "host_id, lower((login)::text)", name: "index_owners_on_host_id_lower_login", unique: true
    t.index ["host_id", "uuid"], name: "index_owners_on_host_id_uuid", unique: true
    t.index ["last_synced_at"], name: "index_owners_on_last_synced_at"
  end

  create_table "package_usages", force: :cascade do |t|
    t.string "ecosystem"
    t.string "name"
    t.bigint "dependents_count", default: 0
    t.integer "repo_ids", default: [], array: true
    t.json "requirements", default: {}
    t.json "kind", default: {}
    t.json "direct", default: {}
    t.json "package", default: {}
    t.datetime "package_last_synced_at"
    t.datetime "created_at"
    t.datetime "updated_at"
    t.index ["ecosystem", "name"], name: "index_package_usages_on_ecosystem_and_name"
    t.index ["package_last_synced_at"], name: "index_package_usages_on_package_last_synced_at"
  end

  create_table "registries", force: :cascade do |t|
    t.string "name"
    t.string "url"
    t.string "ecosystem"
    t.boolean "default", default: false
    t.integer "packages_count", default: 0
    t.string "github"
    t.json "metadata", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "repositories", force: :cascade do |t|
    t.integer "host_id"
    t.string "uuid"
    t.string "full_name"
    t.string "owner"
    t.string "main_language"
    t.boolean "archived"
    t.boolean "fork"
    t.string "description"
    t.datetime "pushed_at"
    t.integer "size"
    t.integer "stargazers_count"
    t.integer "open_issues_count"
    t.integer "forks_count"
    t.integer "subscribers_count"
    t.string "default_branch"
    t.datetime "last_synced_at"
    t.string "etag"
    t.string "topics", default: [], array: true
    t.string "latest_commit_sha"
    t.string "homepage"
    t.string "language"
    t.boolean "has_issues"
    t.boolean "has_wiki"
    t.boolean "has_pages"
    t.string "mirror_url"
    t.string "source_name"
    t.string "license"
    t.boolean "private"
    t.string "status"
    t.string "scm"
    t.boolean "pull_requests_enabled"
    t.string "logo_url"
    t.json "metadata", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.datetime "dependencies_parsed_at"
    t.string "dependency_job_id"
    t.datetime "tags_last_synced_at"
    t.datetime "usage_updated_at"
    t.boolean "files_changed"
    t.json "commit_stats"
    t.string "previous_names", default: [], array: true
    t.integer "tags_count"
    t.index "host_id, lower((full_name)::text)", name: "index_repositories_on_host_id_lower_full_name", unique: true
    t.index ["dependencies_parsed_at"], name: "index_repositories_on_dependencies_parsed_at"
    t.index ["dependency_job_id"], name: "index_repositories_on_dependency_job_id"
    t.index ["host_id", "uuid"], name: "index_repositories_on_host_id_uuid", unique: true
    t.index ["last_synced_at"], name: "index_repositories_on_last_synced_at"
    t.index ["owner"], name: "index_repositories_on_owner"
    t.index ["previous_names"], name: "index_repositories_on_previous_names", using: :gin
    t.index ["topics"], name: "index_repositories_on_topics", using: :gin
  end

  create_table "tags", force: :cascade do |t|
    t.integer "repository_id"
    t.string "name"
    t.string "sha"
    t.string "kind"
    t.datetime "published_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.datetime "dependencies_parsed_at"
    t.string "dependency_job_id"
    t.index ["repository_id"], name: "index_tags_on_repository_id"
  end

end
