# OBRIGATÓRIO PARA UBUNTU: Configura o driver NULL antes de carregar as bibliotecas gráficas
ENV["GKSwstype"] = "100" 

using JuMP
using GLPK
using LinearAlgebra
using DelimitedFiles
using Combinatorics
using Plots
using Random

include("pchm_solver.jl")

# 2. LEITOR COM TRATAMENTO DE EXCEÇÃO COMPLETO (CORRIGIDO)
function ler_instancia_po(caminho_arquivo::String)
    linhas = filter(l -> !isempty(strip(l)) && !startswith(strip(l), "#"), readlines(caminho_arquivo))
    if isempty(linhas) error("Arquivo completamente vazio.") end
    
    # CORREÇÃO DEFINITIVA: Acessamos a primeira string usando o índice [1] antes de dar o split
    primeira_linha = split(linhas[1])
    
    if length(primeira_linha) == 1
        n = parse(Int, primeira_linha[1])
        matriz = zeros(Float64, n, n)
        for i in 1:n
            valores = split(linhas[i+1])
            for j in 1:n matriz[i, j] = parse(Float64, valores[j]) end
        end
        return n, matriz
    else
        error("Formato inválido.")
    end
end

# INTERFACE GRÁFICA: MODELO DE MAPA ESPALHADO EM 2D (SISTEMA DE COORDENADAS REAIS)
function gerar_grafico_rota(n::Int, arcos_ativos::Vector{Tuple{Int,Int}}, nome_instancia::String, pasta_salvar::String)
    if !ispath(pasta_salvar) mkdir(pasta_salvar) end
    if isempty(arcos_ativos) return end 

    gr()

    # Recria exatamente a mesma posição geográfica usada na geração do arquivo correspondente
    semente = occursin("simetrico", nome_instancia) ? 12 : 34
    Random.seed!(semente)
    x_nos = rand(5.0:95.0, n)
    y_nos = rand(5.0:95.0, n)
    
    p = plot(
        title = "Mapa Logístico Rastreável (N = $n)\nInstancia: $nome_instancia",
        titlefont = font(12, :bold),
        size = (1100, 850),
        grid = true,
        gridalpha = 0.1,
        background_color = :white
    )
    
    # Organizar a sequência lógica da rota partindo do nó 1 para pintar o gradiente
    adj_dict = Dict(i => j for (i, j) in arcos_ativos)
    sequencia_caminho = Int[]
    atual = 1
    push!(sequencia_caminho, atual)
    while haskey(adj_dict, atual) && length(sequencia_caminho) < n
        atual = adj_dict[atual]
        push!(sequencia_caminho, atual)
    end

    # 1. Desenhar a rota com uma paleta de degradê (Do Verde ao Roxo/Vermelho)
    cores_gradiente = cgrad(:viridis, length(sequencia_caminho)-1, categorical=true)
    
    for idx in 1:(length(sequencia_caminho)-1)
        i = sequencia_caminho[idx]
        j = sequencia_caminho[idx+1]
        
        # Desenha o segmento de reta com a cor da sua etapa correspondente
        plot!([x_nos[i], x_nos[j]], [y_nos[i], y_nos[j]], 
            color = cores_gradiente[idx], 
            linewidth = 2.5, 
            alpha = 0.9,
            label = ""
        )
        
        # Marcador de seta no meio do segmento
        mx, my = (x_nos[i] + x_nos[j])/2, (y_nos[i] + y_nos[j])/2
        scatter!([mx], [my], marker=:utriangle, markersize=5, color=cores_gradiente[idx], markerstrokewidth=0, label="")
    end
    
    # 2. Desenhar as Cidades Intermediárias
    scatter!(x_nos, y_nos, markersize=6, color=:lightgrey, markerstrokecolor=:black, markerstrokewidth=0.5, label="Cidades do Percurso")
    
    # 3. Destaque Brutal para Início e Fim
    scatter!([x_nos[1]], [y_nos[1]], color=:lime, markersize=14, marker=:square, label="⚡ INÍCIO (Cidade 1)")
    scatter!([x_nos[n]], [y_nos[n]], color=:crimson, markersize=14, marker=:star8, label="🏁 FIM (Cidade $n)")
    
    # 4. Rótulos Numéricos das Cidades
    for i in 1:n
        annotate!(x_nos[i], y_nos[i] + 2.5, text(string(i), :black, :center, :bold, 6))
    end
    
    nome_imagem = replace(nome_instancia, ".txt" => ".png")
    caminho_imagem = joinpath(pasta_salvar, nome_imagem)
    savefig(p, caminho_imagem)
    println("     [🖼️] MAPA LOGÍSTICO GERADO COM GRADIENTE: $caminho_imagem")
end

function executar_lote_total(pasta_instancias::String, arquivo_saida::String, pasta_graficos::String)
    println("\n[ETAPA 2] Processando os cenários euclidianos via JuMP + GLPK...")
    arquivos = sort(readdir(pasta_instancias))
    open(arquivo_saida, "w") do io
        write(io, "Instancia;Leitura_Status;Otimizacao_Status;Custo_Total;Caminho_Valido\n")
        for arq in arquivos
            caminho_completo = joinpath(pasta_instancias, arq)
            println("   " * "-"^76)
            println("   ▶ Analisando: $arq")
            leitura, otimizacao, custo, valido = "SUCESSO", "N/A", "N/A", "N/A"
            try
                n, Matriz_Custo = ler_instancia_po(caminho_completo)
                obj_int, arcos_int, status_solv = resolver_PCHM_MTZ(Matriz_Custo, inteiro=true, tempo_limite_seg=45)
                otimizacao = string(status_solv)
                if status_solv == OPTIMAL || status_solv == TIME_LIMIT
                    custo = string(round(obj_int, digits=2))
                    caminho_valido = verificar_caminho_valido(arcos_int, n, 1, n)
                    valido = string(caminho_valido)
                    println("     [✔] Concluido! Custo = $custo | Rota Valida? = $valido")
                    gerar_grafico_rota(n, arcos_int, arq, pasta_graficos)
                else
                    println("     [⚠️] Solver parou: Motivo = $status_solv")
                end
            catch e
                leitura = "ERRO_FORMATO"
                println("     [❌] Bloqueado: ", sprint(showerror, e))
            end
            write(io, "$arq;$leitura;$otimizacao;$custo;$valido\n")
        end
    end
end

executar_lote_total("instancias", "resultados_cenarios_completos.csv", "graficos")
println("\n[✔] PIPELINE FINALIZADO COM SUCESSO!")
