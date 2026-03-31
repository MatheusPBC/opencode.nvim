# Profiles de Contexto Configuráveis - Design Spec

## Resumo

Implementar suporte a profiles de contexto nomeados e configuráveis, com persistência local do plugin. Um profile é um conjunto nomeado de contextos padrão (e.g., `code_review` → `@buffer, @diff, @diagnostics`).

## Decisões de Produto (Fechadas)

1. **Persistência**: Arquivo local em `stdpath("data")` (fora da repo do usuário)
2. **Escopo**: Profile global + override por projeto
3. **Precedência**: explícito → projeto → global → default
4. **Identificação de projeto**: git root com fallback para cwd

## Arquitetura

### Novos Arquivos

| Arquivo | Responsabilidade |
|---------|------------------|
| `lua/opencode/profiles.lua` | Resolução de profile, identificação de projeto, API interna |
| `lua/opencode/state.lua` | Persistência JSON em stdpath("data") |
| `lua/opencode/ui/select_profiles.lua` | Picker de profiles |

### Modificações

| Arquivo | Mudança |
|---------|---------|
| `lua/opencode/config.lua` | + campo `profiles` na configuração |
| `lua/opencode/api/prompt.lua` | + integração com profile resolvido |
| `lua/opencode.lua` | + API pública: get/set profile global e do projeto |

## Detalhes de Implementação

### 1. state.lua - Persistência

```lua
-- Caminho: stdpath("data")/opencode/profiles.json
-- Formato:
{
  "global_profile": "default",
  "project_overrides": {
    "<project_key>": "<profile_name>"
  }
}

-- Operações:
- M.load() -> table
- M.save(data) -> nil
- M.get_global_profile() -> string|nil
- M.set_global_profile(name) -> nil
- M.get_project_override(project_key) -> string|nil
- M.set_project_override(project_key, name) -> nil
- M.clear_project_override(project_key) -> nil
```

### 2. profiles.lua - Resolução

```lua
-- Identificação de projeto:
M.get_project_key() -> string
  - Tenta git root: vim.fs.root(".git")
  - Fallback: vim.fn.getcwd()

-- Resolução de profile:
M.resolve(opts) -> string
  -- opts.explicit: profile passado diretamente
  -- Precedência: explicit > project > global > "default"

-- Obter contextos do profile:
M.get_contexts(profile_name) -> string[]
  -- Returns contexts from config or empty for "default"

-- API pública (reexportada em opencode.lua):
M.get_global_profile() -> string
M.set_global_profile(name) -> nil
M.get_project_profile() -> string
M.set_project_profile(name) -> nil
M.clear_project_profile() -> nil
M.list_profiles() -> string[]
M.get_active_profile() -> string
```

### 3. config.lua - Configuração

```lua
-- Novo campo em opencode.Opts:
---@field profiles? table<string, string[]> Profile name -> list of context placeholders

-- Defaults:
profiles = {
  default = {} -- contexts vazios, usa comportamento atual
}
```

### 4. api/prompt.lua - Integração

```lua
-- Na função prompt():
-- 1. Resolver profile ativo
local profile_name = profiles.resolve({ explicit = opts.profile })
-- 2. Obter contextos do profile
local profile_contexts = profiles.get_contexts(profile_name)
-- 3. Adicionar contextos do profile ao prompt (concats com prompt original)
-- 4. Continuar fluxo normal
```

### 5. ui/select_profiles.lua - Picker

```lua
-- Ações disponíveis:
-- 1. Set as global profile
-- 2. Set as project profile
-- 3. Clear project override (se houver)

-- Formato:
-- [G] prof_name   description
-- [P] prof_name   description (se for override do projeto atual)
-- [A] prof_name   description (se for global ativo)
```

### 6. opencode.lua - API Pública

```lua
-- Novas funções:
M.get_profile() -> string          -- Profile ativo (resolvido)
M.set_profile_global(name) -> nil  -- Define profile global
M.set_profile_project(name) -> nil -- Define override para projeto atual
M.clear_profile_project() -> nil  -- Limpa override do projeto atual
M.select_profile() -> Promise      -- Abre picker de profiles
```

## Backward Compatibility

- Se `opts.profiles` não for configurado, usa `default` com contexts vazios
- `default` = comportamento atual (sem contexts automáticos)
- Fluxo existente de `ask()` e `prompt()` continua funcionando sem modificação

## Critérios de Aceite

- [ ] Profiles podem ser declarados no setup/config
- [ ] Existe resolução automática com precedência definida
- [ ] Persistência de profile global funciona
- [ ] Persistência de override por projeto funciona
- [ ] Projeto identificado por git root com fallback cwd
- [ ] ask/prompt usa profile resolvido sem quebrar fluxo antigo
- [ ] API pública funcional
- [ ] Picker de profiles funcional
- [ ] Código Lua válido (luac -p)
- [ ] nenhuma API principal quebrada

## Testes Manuais (Smoke Test)

1. Configurar 2+ profiles
2. Definir profile global
3. Definir override para projeto atual
4. Reiniciar Neovim → confirmar persistência
5. Chamar ask() → verificar profile resolvido
6. Remover override → confirmar fallback para global
7. Testar projeto sem git root → fallback para cwd

## Limitações/Follow-ups para Parte 5

- Picker não integrado ao menu principal (fazer单独)
- Sem keymaps dedicados
- Sem docs ainda
- UI de feedback visual do profile ativo (statusline?)