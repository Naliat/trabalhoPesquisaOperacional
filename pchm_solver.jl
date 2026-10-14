using JuMP
using GLPK
using LinearAlgebra

# ATIVIDADE 1: Função de Verificação de Viabilidade Manual do Caminho
"""
    verificar_caminho_valido(sequencia_arcos::Vector{Tuple{Int,Int}}, n::Int, s::Int, t::Int)

Verifica se uma lista de arcos passados como (origem, destino) descreve um caminho
Hamiltoniano válido iniciando em 's', terminando em 't' e visitando todos os outros
vértices do grafo exatamente uma vez.
"""
function verificar_caminho_valido(sequencia_arcos::Vector{Tuple{Int,Int}}, n::Int, s::Int, t::Int)
    # 1. Deve possuir exatamente n-1 arcos para conectar n vértices sem ciclos
    if length(sequencia_arcos) != n - 1
        return false
    end

    # Criar estruturas de mapeamento para checar os graus dos nós e conexões
    adj = Dict{Int, Int}()
    grau_entrada = zeros(Int, n)
    grau_saida = zeros(Int, n)

    for (i, j) in sequencia_arcos
        # Validar limites dos nós
        if i < 1 || i > n || j < 1 || j > n
            return false
        end
        grau_saida[i] += 1
        grau_entrada[j] += 1
        adj[i] = j
    end

    # 2. Validar restrições de Grau/Fluxo (Equações 3 a 8 do roteiro)
    if grau_saida[s] != 1 || grau_entrada[s] != 0 return false end # Sai de s, não volta para s
    if grau_entrada[t] != 1 || grau_saida[t] != 0 return false end # Chega em t, não sai de t

    for k in 1:n
        if k != s && k != t
            if grau_entrada[k] != 1 || grau_saida[k] != 1
                return false # Nós intermediários devem ter exatamente 1 entrada e 1 saída
            end
        end
    end

    # 3. Validar Conectividade Base: Percorrer o caminho de s até o final para garantir que não há subrotas
    visitados = Set{Int}([s])
    atual = s
    while haskey(adj, atual)
        atual = adj[atual]
        push!(visitados, atual)
        if atual == t
            break
        end
    end

    # O caminho só é hamiltoniano se o número de nós visitados conectados a partir de s for igual a n
    return length(visitados) == n
end


# ATIVIDADES 2 e 3: Modelo Matemático MTZ (JuMP + GLPK)
"""
    resolver_PCHM_MTZ(Custo::Matrix{Float64}; inteiro::Bool=true, tempo_limite_seg::Int=180)

Constrói e resolve o modelo matemático do PCHM com limites MTZ.
Permite alternar entre o modelo Inteiro Puro e a Relaxação Linear.
"""
function resolver_PCHM_MTZ(Custo::Matrix{Float64}; inteiro::Bool=true, tempo_limite_seg::Int=180)
    n = size(Custo, 1)
    s = 1     # Origem fixada pelo enunciado
    t = n     # Destino fixado pelo enunciado

    # Instanciar o modelo matemático com o GLPK
    modelo = Model(GLPK.Optimizer)
    set_time_limit_sec(modelo, tempo_limite_seg)

    # 2.1 Variáveis de Decisão
    # x[i,j] = 1 se o arco pertence ao caminho (Binário ou Contínuo entre 0 e 1 se for Relaxação)
    if inteiro
        @variable(modelo, x[1:n, 1:n], Bin)
    else
        @variable(modelo, 0 <= x[1:n, 1:n] <= 1)
    end

    # u[i] representa a ordem posicional de visitação do vértice i ao longo da rota
    @variable(modelo, u[1:n], Int)

    # Impedir que o solver selecione arcos diagonais falsos (i, i)
    for i in 1:n
        @constraint(modelo, x[i, i] == 0)
    end

    # 2.1 Função Objetivo: Minimizar a somatória do custo dos arcos selecionados
    @objective(modelo, Min, sum(Custo[i, j] * x[i, j] for i in 1:n, j in 1:n))

    # 2.2 Restrições Funcionais de Grau / Conservação de Fluxo
    @constraint(modelo, sum(x[s, j] for j in 1:n) == 1) # Sai de s (Eq 3)
    @constraint(modelo, sum(x[i, t] for i in 1:n) == 1) # Chega em t (Eq 4)
    @constraint(modelo, sum(x[i, s] for i in 1:n) == 0) # Não retorna a s (Eq 5)
    @constraint(modelo, sum(x[t, j] for j in 1:n) == 0) # Não sai de t (Eq 6)

    # Nós Intermediários (Eq 7 e 8)
    for k in 1:n
        if k != s && k != t
            @constraint(modelo, sum(x[i, k] for i in 1:n) == 1) # Chega em k exatamente uma vez
            @constraint(modelo, sum(x[k, j] for j in 1:n) == 1) # Sai de k exatamente uma vez
        end
    end

    # 3. Restrições Miller-Tucker-Zemlin (MTZ) de Eliminação de Subrotas
    @constraint(modelo, u[s] == 1) # s ocupa a primeira posição (Eq 9)

    for i in 1:n
        for j in 1:n
            if j != s && i != j
                # Equação posicional 10: impede subciclos isolados no grafo
                @constraint(modelo, u[i] - u[j] + n * x[i, j] <= n - 1)
            end
        end
    end

    # Limites das variáveis de ordenação para nós além da origem (Eq 11)
    for i in 1:n
        if i != s
            @constraint(modelo, 2 <= u[i] <= n)
        end
    end

    # Otimizar o modelo matemático
    optimize!(modelo)

    # Coletar métricas finais de retorno
    status = termination_status(modelo)
    
    if status == OPTIMAL || status == TIME_LIMIT
        val_objetivo = objective_value(modelo)
        x_valores = value.(x)
        
        # Extrair a sequência de arcos ativos da solução obtida
        arcos_ativos = Tuple{Int,Int}[]
        for i in 1:n, j in 1:n
            if x_valores[i, j] > 0.5 # Filtro binário
                push!(arcos_ativos, (i, j))
            end
        end
        return val_objetivo, arcos_ativos, status
    else
        return Inf, Tuple{Int,Int}[], status
    end
end