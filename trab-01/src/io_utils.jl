using Plots
using Random

"""
    carregar_instancia_txt(caminho::String)

Lê e valida o formato das instâncias do tipo TXT comum.
"""
function carregar_instancia_txt(caminho::String)
    if !isfile(caminho) || filesize(caminho) == 0
        error("Arquivo vazio ou inexistente.")
    end
    # Filtra linhas vazias removendo espacos em branco nas bordas
    linhas = filter(!isempty, strip.(readlines(caminho)))
    if isempty(linhas)
        error("Arquivo sem conteudo legivel.")
    end
    
    # Extrai a dimensao n contida na primeira linha
    n = tryparse(Int, linhas[1])
    if n === nothing || n < 2
        error("Numero de vertices invalido: $(linhas[1])")
    end
    if length(linhas) < n + 1
        error("Linhas insuficientes: esperado $(n + 1), lido $(length(linhas))")
    end
    
    # Preenche a matriz bidimensional linha por linha
    C = zeros(Float64, n, n)
    for i in 1:n
        tokens = split(linhas[i + 1])
        if length(tokens) != n
            error("Linha $i tem $(length(tokens)) colunas (esperado $n)")
        end
        for j in 1:n
            val = tryparse(Float64, tokens[j])
            if val === nothing
                error("Caractere invalido em ($i, $j): $(tokens[j])")
            end
            if val < 0.0
                error("Custo negativo em ($i, $j): $val")
            end
            C[i, j] = val
        end
    end
    return n, C
end

"""
    carregar_instancia_atsp(caminho::String)

Lê cabeçalhos estruturados e corrige as quebras de linha dos arquivos .atsp da TSPLIB.
"""
function carregar_instancia_atsp(caminho::String)
    if !isfile(caminho) || filesize(caminho) == 0
        error("Arquivo vazio ou inexistente.")
    end
    linhas = readlines(caminho)
    n = 0
    valores_brutos = Float64[]
    na_secao_pesos = false
    
    # Varre a estrutura do arquivo procurando marcas do cabecalho TSPLIB
    for linha in linhas
        linha_limpa = strip(linha)
        if isempty(linha_limpa)
            continue
        end
        # Extrai o valor numerico da dimensao n contida apos o delimitador de dois pontos
        if startswith(uppercase(linha_limpa), "DIMENSION")
            partes = split(linha_limpa, ":")
            n = parse(Int, strip(partes[end]))
        # Identifica a flag de secao de custos para iniciar a coleta sequencial
        elseif startswith(uppercase(linha_limpa), "EDGE_WEIGHT_SECTION")
            na_secao_pesos = true
            continue
        # Interrompe a leitura caso encontre o finalizador oficial do formato
        elseif startswith(uppercase(linha_limpa), "EOF") || startswith(uppercase(linha_limpa), "TOUR_SECTION")
            break
        end
        
        # Junta os dados numericos em um array de fluxo continuo contornando quebras falsas de linha
        if na_secao_pesos
            dados_linha = split(linha_limpa)
            for val in dados_linha
                push!(valores_brutos, parse(Float64, val))
            end
        end
    end
    
    if n == 0 || length(valores_brutos) < n * n
        error("Formato atsp invalido ou pesos insuficientes.")
    end
    
    # Reconstroi o bloco quadrado n x n utilizando os valores lineares processados
    C = zeros(Float64, n, n)
    idx = 1
    for i in 1:n, j in 1:n
        C[i, j] = valores_brutos[idx]
        idx += 1
    end
    return n, C
end

"""
    gerar_grafico_caminho(n::Int, arcos::Vector{Tuple{Int, Int}}, nome_instancia::String, pasta_saida::String)

Gera o mapa plano cartesiano contínuo em degradê para cada resultado viável encontrado.
"""
function gerar_grafico_caminho(n::Int, arcos::Vector{Tuple{Int, Int}}, nome_instancia::String, pasta_saida::String)
    if isempty(arcos) return end
    if !isdir(pasta_saida) mkpath(pasta_saida) end
    gr()
    
    # Fixa uma semente estavel gerada por hash para travar a posicao x,y das cidades no canvas
    semente = hash(nome_instancia) % 10000
    Random.seed!(abs(semente))
    x_nos = rand(5.0:95.0, n)
    y_nos = rand(5.0:95.0, n)
    
    # Inicia a tela de desenho bidimensional limpa com fundo branco
    p = plot(
        title = "PCHM MTZ - $nome_instancia (n = $n)",
        titlefont = font(11, :bold),
        size = (1000, 800),
        grid = true,
        gridalpha = 0.15,
        background_color = :white,
        legend = :topright
    )
    
    # Ordena a sequencia dos nos com base no dicionario de conexao para criar o efeito visual de gradiente
    adj = Dict(u => v for (u, v) in arcos)
    sequencia = Int[]
    atual = 1
    push!(sequencia, atual)
    while haskey(adj, atual) && length(sequencia) < n
        atual = adj[atual]
        push!(sequencia, atual)
    end
    
    # Gera a escala de cores continua (viridis) proporcional ao tamanho do percurso sequencial
    gradiente = cgrad(:viridis, max(1, length(sequencia) - 1), categorical=true)
    if length(sequencia) > 1
        for idx in 1:(length(sequencia) - 1)
            u = sequencia[idx]
            v = sequencia[idx + 1]
            # Desenha o segmento de linha com a respectiva cor do degradê
            plot!([x_nos[u], x_nos[v]], [y_nos[u], y_nos[v]], color = gradiente[idx], linewidth = 2.0, alpha = 0.85, label = "")
            
            # Insere marcadores de direcao triangulares posicionados no ponto medio do segmento
            mx = (x_nos[u] + x_nos[v]) / 2.0
            my = (y_nos[u] + y_nos[v]) / 2.0
            scatter!([mx], [my], marker = :utriangle, markersize = 4, color = gradiente[idx], markerstrokewidth = 0, label = "")
        end
    end
    
    # Plota a dispersao das cidades e destaca com formatos chamativos a Origem (1) e o Destino (N)
    scatter!(x_nos, y_nos, markersize = (n > 50 ? 5 : 7), color = :lightgrey, markerstrokecolor = :black, markerstrokewidth = 0.5, label = "Vertices")
    scatter!([x_nos[1]], [y_nos[1]], color = :lime, markersize = 12, marker = :square, label = "Origem (s=1)")
    scatter!([x_nos[n]], [y_nos[n]], color = :crimson, markersize = 12, marker = :star8, label = "Destino (t=$n)")
    
    # Insere as anotacoes numericas se a dimensao nao poluir a leitura do grafico
    if n <= 60
        for i in 1:n annotate!(x_nos[i], y_nos[i] + 2.0, text(string(i), :black, :center, :bold, 6)) end
    end
    
    # Ajusta o sufixo da imagem para gerar e salvar o arquivo png fisico no disco do Linux
    nome_png = replace(nome_instancia, r"\.(txt|atsp)$" => ".png")
    savefig(p, joinpath(pasta_saida, nome_png))
end
