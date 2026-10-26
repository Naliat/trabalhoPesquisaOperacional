## Link das apresentações 01: https://drive.google.com/drive/folders/1ZqL5MdA_Y1HO547LbfR5RGJldDPoTCyx?usp=sharing

---

### Relatório Técnico
[![Visualizar PDF](https://img.shields.io/badge/Visualizar_Relatório-PDF-red?style=for-the-badge&logo=adobe-acrobat-reader)](./trab-01/relatorioTp1/main.pdf)

> Clique no botão acima para abrir o relatório completo no visualizador do GitHub ou [clique aqui para baixar o PDF](./trab-01/relatorioTp1/main.pdf).


## Como Executar o Trabalho 01

### 1. Acessar a pasta do Trabalho 01
No terminal, entre no diretório do Trabalho 01:
```bash
cd trab-01
```

### 2. Instalar as Dependências (Primeira Execução)
Caso ainda não tenha instalado as dependências do ambiente local (JuMP, Gurobi, Plots, etc.):
```bash
julia --project=. -e 'using Pkg; Pkg.instantiate()'
```

### 3. Executar o Pipeline Completo
Para executar a leitura das instâncias, a relaxação linear (Atividade 2), o modelo inteiro com limite de 3 minutos (Atividade 3), a validação de caminhos (Atividade 1) e a geração dos relatórios e gráficos:
```bash
julia --project=. main.jl
```

Os resultados detalhados serão salvos em:
* `data/resultados_completos_pchm.csv`: Tabela estruturada com custos, tempos, GAP e rotas.
* `data/relatorio_pchm_gurobi.txt`: Log legível em texto puro.
* `graficos/`: Imagens PNG com os mapas e as rotas encontradas em degradê.
* `relatorioTp1/main.pdf`: Relatório técnico consolidado em LaTeX.

---