# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Renan Lucas Vieira Hilário — RL PROJECTS
#
# Boot scene: plays the RL PROJECTS logo, then opens the game's own first
# scene, read from the project setting `rl_projects/next_scene`.
# Skipped when the game is started with user arguments (`-- --night=1`,
# `-- --skip-title`, test runners...) or without a display.
extends Control

const FALLBACK := "res://main.tscn"


func _ready() -> void:
	var skip := not OS.get_cmdline_user_args().is_empty() \
		or DisplayServer.get_name() == "headless"
	if skip:
		_next()
		return
	var splash := RLProjectsSplash.new()
	add_child(splash)
	splash.finished.connect(_next)


func _next() -> void:
	var path: String = ProjectSettings.get_setting("rl_projects/next_scene", FALLBACK)
	get_tree().change_scene_to_file.call_deferred(path)
