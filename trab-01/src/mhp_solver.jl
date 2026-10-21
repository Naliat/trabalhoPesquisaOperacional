using JuMP
using GLPK
using LinearAlgebra

"""
    validate_hamiltonian_path(active_arcs::Vector{Tuple{Int,Int}}, n::Int, s::Int, t::Int)

Verifica se uma lista de arcos passados como (origem, destino) descreve um caminho
Hamiltoniano válido iniciando em 's', terminando em 't' e visitando todos os outros
vértices do grafo exatamente uma vez (Atividade 1).
"""
function validate_hamiltonian_path(active_arcs::Vector{Tuple{Int,Int}}, n::Int, s::Int, t::Int)
    # 1. Deve possuir exatamente n-1 arcos para conectar n vértices sem ciclos
    if length(active_arcs) != n - 1
        return false
    end

    # Criar estruturas de mapeamento para checar os graus dos nós e conexões
    adj_map = Dict{Int, Int}()
    in_degree = zeros(Int, n)
    out_degree = zeros(Int, n)

    for (i, j) in active_arcs
        # Validar limites dos nós
        if i < 1 || i > n || j < 1 || j > n
            return false
        end
        out_degree[i] += 1
        in_degree[j] += 1
        adj_map[i] = j
    end

    # 2. Validar restrições de Grau/Fluxo (Equações 3 a 8 do roteiro)
    if out_degree[s] != 1 || in_degree[s] != 0 return false end # Sai de s, não volta para s
    if in_degree[t] != 1 || out_degree[t] != 0 return false end # Chega em t, não sai de t

    for k in 1:n
        if k != s && k != t
            if in_degree[k] != 1 || out_degree[k] != 1
                return false # Nós intermediários devem ter exatamente 1 entrada e 1 saída
            end
        end
    end

    # 3. Validar Conectividade Base: Percorrer o caminho de s até o final para garantir que não há subrotas
    visited = Set{Int}([s])
    current = s
    while haskey(adj_map, current)
        current = adj_map[current]
        push!(visited, current)
        if current == t
            break
        end
    end

    # O caminho só é hamiltoniano se o número de nós visitados conectados a partir de s for igual a n
    return length(visited) == n
end


"""
    solve_mphp_mtz(cost_matrix::Matrix{Float64}; is_integer::Bool=true, time_limit_sec::Int=180)

Constrói e resolve o modelo matemático do PCHM com limites MTZ.
Permite alternar entre o modelo Inteiro Puro e a Relaxação Linear (Atividades 2 e 3).
"""
function solve_mphp_mtz(cost_matrix::Matrix{Float64}; is_integer::Bool=true, time_limit_sec::Int=180)
    n = size(cost_matrix, 1)
    s = 1     # Origem fixada pelo enunciado
    t = n     # Destino fixado pelo enunciado

    # Instanciar o modelo matemático com o GLPK
    model = Model(GLPK.Optimizer)
    set_time_limit_sec(model, time_limit_sec)

    # --------------------------------------------------------------------------
    # CONFIGURAÇÃO CORRETA DOS PARÂMETROS DE CORTES NATIVOS DO GLPK
    # --------------------------------------------------------------------------
    set_attribute(model, "presolve", 1)  # Ativa o pré-resolvedor (GLP_ON)
    set_attribute(model, "gmi_cuts", 1)  # Ativa os cortes Gomory (gmi_cuts)
    set_attribute(model, "mir_cuts", 1)  # Ativa os cortes Mixed Integer Rounding (mir_cuts)
    # --------------------------------------------------------------------------

    # 2.1 Variáveis de Decisão
    # x[i,j] = 1 se o arco pertence ao caminho (Binário ou Contínuo entre 0 e 1 se for Relaxação)
    if is_integer
        @variable(model, x[1:n, 1:n], Bin)
    else
        @variable(model, 0 <= x[1:n, 1:n] <= 1)
    end

    # u[i] representa a posição de visitação do vértice i ao longo da rota
    @variable(model, u[1:n], Int)

    # Impedir que o solver selecione arcos diagonais falsos (i, i)
    for i in 1:n
        @constraint(model, x[i, i] == 0)
    end

    # 2.1 Função Objetivo: Minimizar a somatória do custo dos arcos selecionados
    @objective(model, Min, sum(cost_matrix[i, j] * x[i, j] for i in 1:n, j in 1:n))

    # 2.2 Restrições Funcionais de Grau / Conservação de Fluxo
    @constraint(model, sum(x[s, j] for j in 1:n) == 1) # Sai de s (Eq 3)
    @constraint(model, sum(x[i, t] for i in 1:n) == 1) # Chega em t (Eq 4)
    @constraint(model, sum(x[i, s] for i in 1:n) == 0) # Não retorna a s (Eq 5)
    @constraint(model, sum(x[t, j] for j in 1:n) == 0) # Não sai de t (Eq 6)

    # Nós Intermediários (Eq 7 e 8)
    for k in 1:n
        if k != s && k != t
            @constraint(model, sum(x[i, k] for i in 1:n) == 1) # Chega em k exatamente uma vez
            @constraint(model, sum(x[k, j] for j in 1:n) == 1) # Sai de k exatamente uma vez
        end
    end

    # 3. Restrições Miller-Tucker-Zemlin (MTZ) de Eliminação de Subrotas
    @constraint(model, u[s] == 1) # s ocupa a primeira posição (Eq 9)

    for i in 1:n
        for j in 1:n
            if j != s && i != j
                # Equação posicional 10: impede subciclos isolados no grafo
                @constraint(model, u[i] - u[j] + n * x[i, j] <= n - 1)
            end
        end
    end

    # Limites das variáveis de ordenação para nós além da origem (Eq 11)
    for i in 1:n
        if i != s
            @constraint(model, 2 <= u[i] <= n)
        end
    end

    # Otimizar o modelo matemático
    optimize!(model)

    # Coletar métricas finais de retorno
    status = termination_status(model)
    
    if status == OPTIMAL || status == TIME_LIMIT
        obj_value = objective_value(model)
        x_values = value.(x)
        
        # Extrair a sequência de arcos ativos da solução obtida
        active_arcs = Tuple{Int,Int}[]
        for i in 1:n, j in 1:n
            if x_values[i, j] > 0.5 # Filtro binário
                push!(active_arcs, (i, j))
            end
        end
        return obj_value, active_arcs, status
    else
        return Inf, Tuple{Int,Int}[], status
    end
end
