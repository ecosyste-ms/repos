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

ActiveRecord::Schema[7.0].define(version: 2022_07_07_120357) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_stat_statements"
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
    t.index ["manifest_id"], name: "index_dependencies_on_manifest_id"
  end

  create_table "hosts", force: :cascade do |t|
    t.string "name"
    t.string "url"
    t.string "kind"
    t.integer "repositories_count", default: 0
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
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
    t.index ["repository_id"], name: "index_manifests_on_repository_id"
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
    t.string "pull_requests_enabled"
    t.string "logo_url"
    t.json "metadata", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.datetime "dependencies_parsed_at"
    t.string "dependency_job_id"
    t.index "host_id, lower((full_name)::text)", name: "index_repositories_on_host_id_lower_full_name", unique: true
    t.index ["dependencies_parsed_at"], name: "index_repositories_on_dependencies_parsed_at"
    t.index ["host_id", "uuid"], name: "index_repositories_on_host_id_uuid", unique: true
    t.index ["last_synced_at"], name: "index_repositories_on_last_synced_at"
  end

  create_table "tags", force: :cascade do |t|
    t.integer "repository_id"
    t.string "name"
    t.string "sha"
    t.string "kind"
    t.datetime "published_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

end
