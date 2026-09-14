---@meta
-- This file contains type definitions only (no runtime code)

---@class StagedComment
---@field id string Unique identifier (UUID v4)
---@field file_path string Absolute path to the file being commented
---@field start_line integer 1-based start line number
---@field end_line integer 1-based end line number (inclusive)
---@field text string The comment text content
---@field created_at integer Unix timestamp when created
---@field created_order integer Monotonic creation order
---@field extmark_id integer|nil Extmark ID for position tracking (nil if not yet placed)

---@class StagedFileState
---@field bufnr integer Buffer number for this file
---@field comments table<string, StagedComment> Comments keyed by their UUID

---@class StagedKeymap
---@field mode string
---@field lhs string

---@class StagedSession
---@field tabpage integer Neovim tabpage ID (from codediff)
---@field active boolean Whether the state-owned session is active
---@field root string Stable root used for relative export paths
---@field files table<string, StagedFileState> File states keyed by absolute path
---@field current_file string|nil Currently active file path
---@field sidebar_bufnr integer|nil Sidebar buffer (nil if not created)
---@field sidebar_winid integer|nil Sidebar window (nil if not visible)
---@field visible boolean Whether sidebar is currently visible
---@field ns_id integer Position extmark namespace ID for this session
---@field indicator_ns_id integer Inline indicator namespace ID for this session
---@field history_ns_id integer Dormant history extmark namespace ID for this session
---@field keymaps table<integer, table<string, StagedKeymap>> Buffer-local keymaps owned by the session
---@field history StagedHistory Comment mutation history for this session

---@class StagedHistory
---@field undo StagedHistoryEntry[]
---@field redo StagedHistoryEntry[]

---@class StagedHistoryEntry
---@field action string
---@field snapshot StagedSnapshot

---@class StagedSnapshot
---@field files table<string, StagedSnapshotFile>

---@class StagedSnapshotFile
---@field bufnr integer
---@field comments StagedSavedComment[]

---@class StagedSavedComment
---@field id string
---@field file_path string
---@field start_line integer
---@field end_line integer
---@field text string
---@field created_at integer
---@field created_order integer
---@field history_extmark_id integer|nil

---@class StagedConfig
---@field activation StagedActivationConfig
---@field keymaps StagedKeymapsConfig
---@field sidebar StagedSidebarConfig
---@field inline StagedInlineConfig
---@field input StagedInputConfig
---@field export StagedExportConfig

---@class StagedActivationConfig
---@field mode 'auto'|'manual' How to activate on codediff sessions

---@class StagedKeymapsConfig
---@field prefix string Leader key prefix (default: '<leader>c')
---@field add string Key for add (appended to prefix)
---@field edit string Key for edit
---@field delete string Key for delete
---@field clear_all string Key for clear all
---@field undo string Key for undo
---@field redo string Key for redo
---@field toggle_sidebar string Key for sidebar toggle
---@field export_clipboard string Key for clipboard export
---@field export_buffer string Key for buffer export
---@field export_file string Key for file export
---@field next_comment string Absolute key for next comment
---@field prev_comment string Absolute key for prev comment

---@class StagedSidebarConfig
---@field position 'left'|'right' Which side to show sidebar
---@field width integer Sidebar width in columns
---@field height integer Sidebar height when split below explorer
---@field auto_show boolean Auto-show when first comment added

---@class StagedInlineConfig
---@field style 'sign'|'virtual_text'|'line_highlight' Indicator style
---@field sign_icon string Icon for sign column
---@field virtual_text_format string Format string for virtual text
---@field priority integer Extmark priority for inline decorations (0..65535, default 150)

---@class StagedInputConfig
---@field style 'floating'|'inline' Input window style

---@class StagedExportConfig
---@field include_code boolean Include code snippets in export
---@field format 'markdown'|'plain'|'json' Export format
