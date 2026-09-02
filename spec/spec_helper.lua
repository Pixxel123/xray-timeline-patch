-- Minimal helper: the presence-map module is pure Lua; specs need only paths.
-- (The runner sets package.path too; kept so specs that require this work alone.)
package.path = "./?.lua;./src/?.lua;" .. package.path
