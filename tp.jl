using JuMP
using Gurobi
using PyCall
using Printf
using Random
using ProgressMeter

const sns = pyimport("seaborn")
const plt = pyimport("matplotlib.pyplot")

function verificar_caminho_valido(n::Int, arcos::Vector{Tuple{Int, Int}}, s::Int, t::Int)
    if length(arcos) != n - 1
        return false
    end

    grau_saida = zeros(Int, n)
    grau_entrada = zeros(Int, n)
    adj = Dict{Int, Int}()

    for (u, v) in arcos
        if u < 1 || u > n || v < 1 || v > n || u == v
            return false
        end
        grau_saida[u] += 1
        grau_entrada[v] += 1
        adj[u] = v
    end

    if grau_saida[s] != 1 || grau_entrada[s] != 0
        return false
    end

    if grau_entrada[t] != 1 || grau_saida[t] != 0
        return false
    end

    for k in 1:n
        if k != s && k != t
            if grau_saida[k] != 1 || grau_entrada[k] != 1
                return false
            end
        end
    end

    visitados = Set{Int}([s])
    atual = s
    while haskey(adj, atual)
        proximo = adj[atual]
        if in(proximo, visitados)
            return false
        end
        push!(visitados, proximo)
        atual = proximo
    end

    return (atual == t) && (length(visitados) == n)
end

function resolver_pchm_gurobi(n::Int, C::Matrix{Float64}; s::Int=1, t::Int=n, relaxacao::Bool=false, time_limit_sec::Float64=180.0)
    V = 1:n
    model = Model(Gurobi.Optimizer)
    set_silent(model)
    set_time_limit_sec(model, time_limit_sec)

    if relaxacao
        @variable(model, 0.0 <= x[i in V, j in V] <= 1.0)
        @variable(model, u[i in V] >= 0.0)
    else
        @variable(model, x[i in V, j in V], Bin)
        @variable(model, u[i in V] >= 0, Int)
    end

    @objective(model, Min, sum(C[i, j] * x[i, j] for i in V, j in V if i != j))

    for i in V
        @constraint(model, x[i, i] == 0)
    end
    
    @constraint(model, sum(x[s, j] for j in V if j != s) == 1)
    @constraint(model, sum(x[i, t] for i in V if i != t) == 1)
    @constraint(model, sum(x[i, s] for i in V if i != s) == 0)
    @constraint(model, sum(x[t, j] for j in V if j != t) == 0)

    for k in V
        if k != s && k != t
            @constraint(model, sum(x[i, k] for i in V if i != k) == 1)
            @constraint(model, sum(x[k, j] for j in V if j != k) == 1)
        end
    end

    @constraint(model, u[s] == 1)

    for i in V
        if i != s
            @constraint(model, u[i] >= 2)
            @constraint(model, u[i] <= n)
        end
    end

    for i in V, j in V
        if j != s && i != j
            @constraint(model, u[i] - u[j] + n * x[i, j] <= n - 1)
        end
    end

    tempo_exec = @elapsed optimize!(model)
    st = termination_status(model)
    tem_sol = (result_count(model) > 0)
    custo = tem_sol ? objective_value(model) : Inf

    arcos_solucao = Tuple{Int, Int}[]
    if tem_sol && !relaxacao
        for i in V, j in V
            if i != j && value(x[i, j]) > 0.5
                push!(arcos_solucao, (i, j))
            end
        end
    end

    return (status = st, custo = custo, tempo = tempo_exec, arcos = arcos_solucao)
end

function gerar_instancia_euclidiana(n::Int; seed::Int=42)
    Random.seed!(seed)
    coords_x = rand(n) .* 400.0
    coords_y = rand(n) .* 400.0
    
    C = zeros(Float64, n, n)
    for i in 1:n, j in 1:n
        if i != j
            C[i, j] = round(hypot(coords_x[i] - coords_x[j], coords_y[i] - coords_y[j]), digits=2)
        end
    end
    return n, C, coords_x, coords_y
end

function plotar_com_seaborn(n::Int, coords_x::Vector{Float64}, coords_y::Vector{Float64}, 
                            arcos::Vector{Tuple{Int, Int}}, s::Int, t::Int, arquivo_saida::String)
    sns.set_theme(style="whitegrid", palette="muted")
    fig, ax = plt.subplots(figsize=(11, 9))

    categorias = String[]
    for i in 1:n
        if i == s
            push!(categorias, "Origem (s=$s)")
        elseif i == t
            push!(categorias, "Destino (t=$t)")
        else
            push!(categorias, "Intermediário")
        end
    end

    palette = Dict(
        "Origem (s=$s)" => "#2ecc71", 
        "Destino (t=$t)" => "#e74c3c", 
        "Intermediário" => "#3498db"
    )

    sns.scatterplot(
        x=coords_x, 
        y=coords_y, 
        hue=categorias, 
        palette=palette, 
        s=(n > 50 ? 80 : 130), 
        ax=ax, 
        zorder=3
    )

    for i in 1:n
        ax.text(coords_x[i] + 1.2, coords_y[i] + 1.2, "$i", fontsize=(n > 50 ? 7 : 9), zorder=4)
    end

    for (u, v) in arcos
        ax.annotate(
            "",
            xy=(coords_x[v], coords_y[v]),
            xytext=(coords_x[u], coords_y[u]),
            arrowprops=Dict(
                "arrowstyle" => "->", 
                "color" => "#2c3e50", 
                "lw" => (n > 50 ? 1.0 : 1.5),
                "shrinkA" => 4, 
                "shrinkB" => 4
            ),
            zorder=2
        )
    end

    ax.set_title("PCHM com MTZ (Gurobi) - Rota Ótima (n = $n Vértices)", fontsize=13, weight="bold")
    ax.set_xlabel("Coordenada X")
    ax.set_ylabel("Coordenada Y")
    ax.legend(loc="upper right", frameon=true)

    plt.tight_layout()
    plt.savefig(arquivo_saida, dpi=300)
    plt.close()
end

function main()
    n_vertices = 70
    total_rodadas = 3
    s = 1
    t = n_vertices

    p_bar = Progress(total_rodadas, dt=0.5, desc="Progresso Geral: ", barlen=30)
    resultados = []

    coords_salvas_x = Float64[]
    coords_salvas_y = Float64[]
    primeira_lp = nothing
    primeira_ip = nothing
    primeiro_gap = 0.0
    primeiro_valido = false

    for rodada in 1:total_rodadas
        n, C, px, py = gerar_instancia_euclidiana(n_vertices, seed=200 + rodada)

        res_lp = resolver_pchm_gurobi(n, C; s=s, t=t, relaxacao=true)
        res_ip = resolver_pchm_gurobi(n, C; s=s, t=t, relaxacao=false, time_limit_sec=180.0)

        valido = verificar_caminho_valido(n, res_ip.arcos, s, t)
        gap = (res_ip.custo != Inf && res_ip.custo > 0) ? ((res_ip.custo - res_lp.custo) / res_ip.custo) * 100.0 : 0.0

        push!(resultados, (rodada=rodada, lp=res_lp, ip=res_ip, gap=gap, valido=valido))

        if rodada == 1
            coords_salvas_x = px
            coords_salvas_y = py
            primeira_lp = res_lp
            primeira_ip = res_ip
            primeiro_gap = gap
            primeiro_valido = valido
        end

        next!(p_bar)
    end

    plotar_com_seaborn(n_vertices, coords_salvas_x, coords_salvas_y, primeira_ip.arcos, s, t, "caminho_seaborn_gurobi_70.png")

    caminho_ordenado = [s]
    mapa_arcos = Dict(u => v for (u, v) in primeira_ip.arcos)
    atual = s
    while haskey(mapa_arcos, atual)
        prox = mapa_arcos[atual]
        push!(caminho_ordenado, prox)
        atual = prox
    end

    open("relatorio_pchm_gurobi.txt", "w") do f
        println(f, "RELATÓRIO COMPARATIVO: PCHM COM RESTRIÇÕES MTZ (SOLVER GUROBI)")
        println(f, "UFC - Campus Quixadá | Disciplina: Pesquisa Operacional")
        println(f, "PARÂMETROS DO MODELO:")
        println(f, "  - Número de Vértices (n): $n_vertices")
        println(f, "  - Vértice de Origem (s): $s")
        println(f, "  - Vértice de Destino (t): $t")
        println(f, "  - Solucionador: Gurobi Optimizer")
        println(f, "  - Quantidade de Arcos Esperados: $(n_vertices - 1)")
        println(f, "RESUMO DE TODAS AS RODADAS EXECUTADAS:")
        for r in resultados
            println(f, @sprintf("  Rodada %02d | Z_LP: %8.2f (%5.2fs) | Z_IP: %8.2f (%6.2fs) | GAP: %5.2f%% | Válido: %s",
                    r.rodada, r.lp.custo, r.lp.tempo, r.ip.custo, r.ip.tempo, r.gap, r.valido))
        end
        println(f, "DETALHAMENTO DA INSTÂNCIA PILOTO (RODADA 01):")
        println(f, @sprintf("  - Relaxação Linear (Z_LP):  %.4f", primeira_lp.custo))
        println(f, @sprintf("  - Tempo Relaxação:          %.4f segundos", primeira_lp.tempo))
        println(f, "  - Status Linear:            $(primeira_lp.status)")
        println(f, "")
        println(f, @sprintf("  - Solução Inteira (Z_IP):    %.4f", primeira_ip.custo))
        println(f, @sprintf("  - Tempo Solução Inteira:    %.4f segundos", primeira_ip.tempo))
        println(f, "  - Status Inteiro:           $(primeira_ip.status)")
        println(f, "")
        println(f, @sprintf("  - GAP de Relaxação:         %.2f%%", primeiro_gap))
        println(f, "  - Solução Válida (Ativ. 1): $primeiro_valido")
        println(f, "  - Rota Percorrida:          ", join(caminho_ordenado, " -> "))
    end
end

main()