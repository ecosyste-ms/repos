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

ActiveRecord::Schema[8.1].define(version: 2026_01_10_194159) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "dependencies", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.boolean "direct", default: false
    t.string "ecosystem"
    t.string "kind"
    t.integer "manifest_id"
    t.boolean "optional", default: false
    t.string "package_name"
    t.integer "repository_id"
    t.string "requirements"
    t.datetime "updated_at", null: false
    t.index ["ecosystem", "package_name"], name: "index_dependencies_on_ecosystem_and_package_name"
    t.index ["manifest_id"], name: "index_dependencies_on_manifest_id"
    t.index ["package_name", "ecosystem"], name: "index_dependencies_on_package_name_and_ecosystem"
  end

  create_table "exports", force: :cascade do |t|
    t.string "bucket_name"
    t.datetime "created_at", null: false
    t.string "date"
    t.integer "repositories_count"
    t.datetime "updated_at", null: false
  end

  create_table "hosts", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "kind"
    t.text "last_error"
    t.string "name"
    t.string "org"
    t.integer "owners_count", default: 0
    t.integer "repositories_count", default: 0
    t.integer "response_time"
    t.text "robots_txt_content"
    t.string "robots_txt_status"
    t.datetime "robots_txt_updated_at"
    t.string "status"
    t.datetime "status_checked_at"
    t.datetime "updated_at", null: false
    t.string "url"
    t.string "version"
  end

  create_table "imports", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "error_message"
    t.string "filename"
    t.datetime "imported_at"
    t.integer "push_events_count"
    t.integer "release_events_count"
    t.integer "releases_synced_count"
    t.integer "repositories_synced_count"
    t.boolean "success"
    t.datetime "updated_at", null: false
    t.index ["filename"], name: "index_imports_on_filename", unique: true
  end

  create_table "manifests", force: :cascade do |t|
    t.string "branch"
    t.datetime "created_at", null: false
    t.string "ecosystem"
    t.string "filepath"
    t.string "kind"
    t.integer "repository_id"
    t.string "sha"
    t.integer "tag_id"
    t.datetime "updated_at", null: false
    t.index ["repository_id"], name: "index_manifests_on_repository_id"
    t.index ["tag_id"], name: "index_manifests_on_tag_id"
  end

  create_table "owners", force: :cascade do |t|
    t.string "avatar_url"
    t.string "company"
    t.datetime "created_at", null: false
    t.string "description"
    t.string "email"
    t.integer "followers"
    t.integer "following"
    t.boolean "hidden"
    t.integer "host_id"
    t.string "kind"
    t.datetime "last_synced_at"
    t.string "location"
    t.string "login"
    t.json "metadata", default: {}
    t.string "name"
    t.integer "repositories_count", default: 0
    t.bigint "total_stars"
    t.string "twitter"
    t.datetime "updated_at", null: false
    t.string "uuid"
    t.string "website"
    t.index "host_id, lower((login)::text)", name: "index_owners_on_host_id_lower_login", unique: true
    t.index ["host_id", "uuid"], name: "index_owners_on_host_id_uuid", unique: true
    t.index ["last_synced_at"], name: "index_owners_on_last_synced_at"
  end

  create_table "package_usages", force: :cascade do |t|
    t.datetime "created_at"
    t.bigint "dependents_count", default: 0
    t.string "ecosystem"
    t.string "key"
    t.string "name"
    t.json "package", default: {}
    t.datetime "package_last_synced_at"
    t.integer "repository_usages_count"
    t.datetime "updated_at"
    t.index ["ecosystem", "name"], name: "index_package_usages_on_ecosystem_and_name"
    t.index ["key"], name: "index_package_usages_on_key", unique: true
    t.index ["package_last_synced_at"], name: "index_package_usages_on_package_last_synced_at"
  end

  create_table "registries", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.boolean "default", default: false
    t.string "ecosystem"
    t.string "github"
    t.json "metadata", default: {}
    t.string "name"
    t.integer "packages_count", default: 0
    t.datetime "updated_at", null: false
    t.string "url"
  end

  create_table "releases", force: :cascade do |t|
    t.json "assets", default: []
    t.string "author"
    t.text "body"
    t.datetime "created_at", null: false
    t.boolean "draft"
    t.datetime "last_synced_at"
    t.string "name"
    t.boolean "prerelease"
    t.datetime "published_at"
    t.integer "repository_id", null: false
    t.integer "tag_id"
    t.string "tag_name"
    t.string "target_commitish"
    t.datetime "updated_at", null: false
    t.string "uuid"
    t.index ["repository_id", "published_at"], name: "index_releases_on_repository_id_and_published_at", order: { published_at: "DESC NULLS LAST" }
  end

  create_table "repositories", force: :cascade do |t|
    t.boolean "archived"
    t.json "commit_stats"
    t.datetime "created_at", null: false
    t.string "default_branch"
    t.datetime "dependencies_parsed_at"
    t.string "dependency_job_id"
    t.string "description"
    t.string "etag"
    t.boolean "files_changed"
    t.boolean "fork"
    t.integer "forks_count"
    t.string "full_name"
    t.boolean "has_issues"
    t.boolean "has_pages"
    t.boolean "has_wiki"
    t.string "homepage"
    t.integer "host_id"
    t.string "language"
    t.datetime "last_synced_at"
    t.string "latest_commit_sha"
    t.string "latest_tag_name"
    t.datetime "latest_tag_published_at"
    t.string "license"
    t.string "logo_url"
    t.string "main_language"
    t.json "metadata", default: {}
    t.string "mirror_url"
    t.integer "open_issues_count"
    t.string "owner"
    t.string "previous_names", default: [], array: true
    t.boolean "private"
    t.boolean "pull_requests_enabled"
    t.datetime "pushed_at"
    t.string "scm"
    t.integer "size"
    t.string "source_name"
    t.integer "stargazers_count"
    t.string "status"
    t.integer "subscribers_count"
    t.integer "tags_count"
    t.datetime "tags_last_synced_at"
    t.boolean "template"
    t.string "template_full_name"
    t.string "topics", default: [], array: true
    t.datetime "updated_at", null: false
    t.datetime "usage_last_calculated"
    t.datetime "usage_updated_at"
    t.string "uuid"
    t.index "host_id, lower((full_name)::text)", name: "index_repositories_on_host_id_lower_full_name", unique: true
    t.index ["dependencies_parsed_at"], name: "index_repositories_on_dependencies_parsed_at"
    t.index ["dependency_job_id"], name: "index_repositories_on_dependency_job_id"
    t.index ["host_id", "uuid"], name: "index_repositories_on_host_id_uuid", unique: true
    t.index ["last_synced_at"], name: "index_repositories_on_last_synced_at"
    t.index ["owner"], name: "index_repositories_on_owner"
    t.index ["previous_names"], name: "index_repositories_on_previous_names", using: :gin
    t.index ["topics"], name: "index_repositories_on_topics", using: :gin
  end

  create_table "repository_usages", force: :cascade do |t|
    t.integer "package_usage_id"
    t.integer "repository_id"
    t.index ["package_usage_id"], name: "index_repository_usages_on_package_usage_id"
    t.index ["repository_id"], name: "index_repository_usages_on_repository_id"
  end

  create_table "scorecards", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.json "data"
    t.datetime "last_synced_at"
    t.bigint "repository_id"
    t.datetime "updated_at", null: false
    t.index ["repository_id"], name: "index_scorecards_on_repository_id"
  end

  create_table "tags", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "dependencies_parsed_at"
    t.string "dependency_job_id"
    t.string "kind"
    t.string "name"
    t.datetime "published_at"
    t.integer "repository_id"
    t.string "sha"
    t.datetime "updated_at", null: false
    t.index ["repository_id", "published_at"], name: "index_tags_on_repository_id_and_published_at", order: { published_at: "DESC NULLS LAST" }
  end

  create_table "topics", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "host_id", null: false
    t.string "name", null: false
    t.integer "repositories_count", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["host_id", "name"], name: "index_topics_on_host_id_and_name", unique: true
    t.index ["host_id", "repositories_count"], name: "index_topics_on_host_id_and_repositories_count"
    t.index ["host_id"], name: "index_topics_on_host_id"
    t.index ["name"], name: "index_topics_on_name"
    t.index ["repositories_count"], name: "index_topics_on_repositories_count"
  end

  add_foreign_key "scorecards", "repositories"
  add_foreign_key "topics", "hosts"
end
