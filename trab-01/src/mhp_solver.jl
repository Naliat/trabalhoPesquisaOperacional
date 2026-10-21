using JuMP
using Gurobi
using LinearAlgebra

"""
    validate_hamiltonian_path(n::Int, active_arcs::Vector{Tuple{Int,Int}}, s::Int, t::Int)

Verifica se uma lista de arcos passados como (origem, destino) descreve um caminho
Hamiltoniano válido iniciando em 's', terminando em 't' e visitando todos os outros
vértices do grafo exatamente uma vez (Atividade 1).
"""
function validate_hamiltonian_path(n::Int, active_arcs::Vector{Tuple{Int,Int}}, s::Int, t::Int)
    # Valida se a quantidade de arcos ativos e igual a n - 1
    if length(active_arcs) != n - 1
        return false
    end

    # Inicializa vetores para contagem de graus de entrada, saida e dicionario de adjacencia
    in_degree = zeros(Int, n)
    out_degree = zeros(Int, n)
    adj_map = Dict{Int, Int}()

    # Varre os arcos para computar os graus e mapear os vizinhos
    for (u, v) in active_arcs
        # Barramento contra indices fora dos limites do grafo ou loops diagonais
        if u < 1 || u > n || v < 1 || v > n || u == v
            return false
        end
        out_degree[u] += 1
        in_degree[v] += 1
        adj_map[u] = v
    end

    # Valida restricoes de borda da origem s: deve apenas sair fluxo
    if out_degree[s] != 1 || in_degree[s] != 0
        return false
    end
    
    # Valida restricoes de borda do destino t: deve apenas chegar fluxo
    if in_degree[t] != 1 || out_degree[t] != 0
        return false
    end

    # Valida se cada nó intermediario possui exatamente uma entrada e uma saida
    for k in 1:n
        if k != s && k != t
            if out_degree[k] != 1 || in_degree[k] != 1
                return false
            end
        end
    end

    # Realiza o rastreamento sequencial para garantir conectividade e bloquear subciclos isolados
    visited = Set{Int}([s])
    current = s
    while haskey(adj_map, current)
        next_node = adj_map[current]
        # Se tentar retornar para um nó ja visitado, detecta um subciclo invalido
        if in(next_node, visited)
            return false
        end
        push!(visited, next_node)
        current = next_node
    end

    # O caminho so e valido se terminou em t e o tamanho da lista de visitados cobre todos os n nós
    return (current == t) && (length(visited) == n)
end

"""
    solve_mphp_model(cost_matrix::Matrix{Float64}; is_integer::Bool=true, time_limit_sec::Real=180.0)

Modela e resolve o PCHM utilizando um solucionador comercial parametrizado de forma generica (Atividades 2 e 3).
"""
function solve_mphp_model(cost_matrix::Matrix{Float64}; is_integer::Bool=true, time_limit_sec::Real=180.0)
    n = size(cost_matrix, 1)
    s = 1     # Origem fixada pelo enunciado
    t = n     # Destino fixado pelo enunciado

    # Instanciar o modelo matematico utilizando o otimizador Gurobi
    model = Model(Gurobi.Optimizer)
    set_silent(model) # Desativa mensagens internas extensas do solver no terminal
    set_time_limit_sec(model, time_limit_sec) # Define o limitador de tempo por instancia

    # --------------------------------------------------------------------------
    # CONFIGURAÇÃO DE ALTA PERFORMANCE NATIVA DO SOLVER COMERCIAL
    # --------------------------------------------------------------------------
    set_attribute(model, "Presolve", 2)  # Ativa o pre-resolvedor agressivo comercial (Nivel 2)
    set_attribute(model, "Cuts", 2)      # Forca a geracao agressiva de planos de corte (Nivel 2)
    # --------------------------------------------------------------------------

    # Instancia as variaveis de decisao de acordo com a flag de relaxacao linear
    if !is_integer
        @variable(model, 0.0 <= x[1:n, 1:n] <= 1.0) # Variavel continua para a Atividade 2
        @variable(model, u[1:n] >= 0.0)
    else
        @variable(model, x[1:n, 1:n], Bin) # Variavel binaria pura para a Atividade 3
        @variable(model, u[1:n] >= 0, Int) # Atributo posicional do MTZ
    end

    # Define a funcao objetivo de minimizacao de custos excluindo a diagonal principal
    @objective(model, Min, sum(cost_matrix[i, j] * x[i, j] for i in 1:n, j in 1:n if i != j))

    # Restricao de barramento diagonal: impede conexoes auto-referenciadas
    for i in 1:n
        @constraint(model, x[i, i] == 0)
    end

    # Aplica as restricoes funcionais de fluxo de grau de entrada e saida da TSPLIB
    @constraint(model, sum(x[s, j] for j in 1:n if j != s) == 1) # Garante saida da origem s
    @constraint(model, sum(x[i, t] for i in 1:n if i != t) == 1) # Garante chegada no destino t
    @constraint(model, sum(x[i, s] for i in 1:n if i != s) == 0) # Impede retorno para a origem s
    @constraint(model, sum(x[t, j] for j in 1:n if j != t) == 0) # Impede saida a partir do destino t

    # Garante a conservacao de fluxo unitario para todos os nós intermediarios do grafo
    for k in 1:n
        if k != s && k != t
            @constraint(model, sum(x[i, k] for i in 1:n if i != k) == 1)
            @constraint(model, sum(x[k, j] for j in 1:n if j != k) == 1)
        end
    end

    # Fixa a posicao inicial da ordenacao posicional MTZ
    @constraint(model, u[s] == 1)
    
    # Define os limites superior e inferior das posicoes dos nós subsequentes
    for i in 1:n
        if i != s
            @constraint(model, 2 <= u[i] <= n)
        end
    end

    # Aplica as restricoes logicas de Miller-Tucker-Zemlin (MTZ) para quebrar subrotas isoladas
    for i in 1:n, j in 1:n
        if j != s && i != j
            @constraint(model, u[i] - u[j] + n * x[i, j] <= n - 1)
        end
    end

    # Aciona o solver comercial e calcula o tempo gasto puramente no processamento interno
    tempo_exec = @elapsed optimize!(model)
    st = termination_status(model)
    tem_sol = (result_count(model) > 0)
    custo = tem_sol ? objective_value(model) : Inf

    # Extrai o vetor de arcos estruturados se houver solucao viavel inteira
    arcos_solucao = Tuple{Int, Int}[]
    if tem_sol && is_integer
        for i in 1:n, j in 1:n
            if i != j && value(x[i, j]) > 0.5
                push!(arcos_solucao, (i, j))
            end
        end
    end

    return (status = st, custo = custo, tempo = tempo_exec, arcos = arcos_solucao)
end
