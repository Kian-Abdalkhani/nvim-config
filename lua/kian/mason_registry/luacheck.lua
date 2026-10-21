return {
	name = "luacheck",
	description = "LuaCheck installed with a compatible Lua 5.4 runtime.",
	homepage = "https://github.com/lunarmodules/luacheck",
	licenses = { "MIT" },
	languages = { "Lua" },
	categories = { "Linter" },
	source = {
		id = "pkg:generic/luacheck@1.2.0",
		supported_platforms = { "unix" },
		build = {
			-- LuaRocks embeds absolute paths, so install in Mason's final package directory.
			staged = false,
			env = { LUACHECK_VERSION = "{{ version }}" },
			run = [[
luacheck_lua_prefix=""
for luacheck_candidate in /opt/homebrew/opt/lua@5.4 /usr/local/opt/lua@5.4; do
  if [ -x "$luacheck_candidate/bin/lua5.4" ]; then
    luacheck_lua_prefix="$luacheck_candidate"
    break
  fi
done
if [ -z "$luacheck_lua_prefix" ]; then
  luacheck_lua_executable="$(command -v lua5.4 || true)"
  if [ -n "$luacheck_lua_executable" ]; then
    luacheck_lua_prefix="$(dirname "$(dirname "$luacheck_lua_executable")")"
  fi
fi
if [ -z "$luacheck_lua_prefix" ]; then
  echo 'LuaCheck needs Lua 5.4 and its development headers.' >&2
  echo 'On macOS: brew install lua@5.4.' >&2
  echo 'Elsewhere, install Lua 5.4 development packages and expose lua5.4 on PATH.' >&2
  exit 1
fi
luarocks --lua-version=5.4 --lua-dir="$luacheck_lua_prefix" install --tree "$PWD" luacheck "$LUACHECK_VERSION"
]],
		},
	},
	bin = { luacheck = "bin/luacheck" },
}
